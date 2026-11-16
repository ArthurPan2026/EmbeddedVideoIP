#include "../../software/video_out.h"

#include <stdio.h>
#include <string.h>

typedef struct {
    uint32_t regs[16];
    uint32_t busy_reads_before_clear;
    uint32_t force_busy;
    uint32_t ctrl_write_count;
    uint32_t first_ctrl_write;
    uint32_t last_ctrl_write;
    uint32_t abort_count;
    uint32_t resume_count;
    uint32_t busy_on_first_vdma_call;
    uint32_t hold_during_vdma;
    uint32_t vdma_calls;
    uint32_t vdma_width;
    uint32_t vdma_height;
    uint32_t vdma_bpp;
    uint32_t vdma_stride;
    uint32_t vdma_initial_frame;
    uint64_t vdma_base;
    int vdma_result;
} FakeVideo;

static uint32_t read_reg(void *context, uint32_t offset)
{
    FakeVideo *fake = (FakeVideo *)context;
    if (offset == 0x10U) {
        if (fake->busy_reads_before_clear != 0U) {
            fake->busy_reads_before_clear--;
            if (fake->busy_reads_before_clear == 0U)
                fake->regs[4] &= ~(1U << 4);
        }
        if (fake->force_busy != 0U)
            fake->regs[4] |= 1U << 4;
    }
    return fake->regs[(offset >> 2) & 15U];
}

static void write_reg(void *context, uint32_t offset, uint32_t value)
{
    FakeVideo *fake = (FakeVideo *)context;
    if (offset == 0x00U) {
        if (fake->ctrl_write_count == 0U)
            fake->first_ctrl_write = value;
        fake->last_ctrl_write = value;
        fake->ctrl_write_count++;
        if ((value & (1U << 11)) != 0U) {
            fake->abort_count++;
            fake->force_busy = 0U;
            fake->regs[4] = (fake->regs[4] & ~(1U << 4)) | (1U << 1);
        }
        if ((value & (1U << 12)) != 0U) {
            fake->resume_count++;
            fake->regs[4] &= ~(1U << 1);
        }
        if ((value & (1U << 8)) != 0U) {
            fake->regs[4] &= ~((1U << 2) | (1U << 1));
            if ((value & 1U) != 0U)
                fake->regs[4] |= 1U;
            else
                fake->regs[4] &= ~1U;
        }
        fake->regs[0] = value & ~((1U << 8) | (1U << 9) | (1U << 10) |
                                  (1U << 11) | (1U << 12));
        return;
    }
    fake->regs[(offset >> 2) & 15U] = value;
    if (offset == 0x34U)
        fake->regs[15] = (fake->regs[15] & ~1U) | (value & 1U);
}

static int configure_vdma(void *context, uint64_t base, uint32_t width,
                          uint32_t height, uint32_t bpp, uint32_t stride, uint32_t initial_frame)
{
    FakeVideo *fake = (FakeVideo *)context;
    fake->busy_on_first_vdma_call = (fake->regs[4] >> 4) & 1U;
    fake->hold_during_vdma = (fake->regs[4] >> 1) & 1U;
    fake->vdma_calls++;
    fake->vdma_base = base;
    fake->vdma_width = width;
    fake->vdma_height = height;
    fake->vdma_bpp = bpp;
    fake->vdma_stride = stride;
    fake->vdma_initial_frame = initial_frame;
    return fake->vdma_result;
}

#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "测试失败：%s\n", m); return 1; } } while (0)

int main(void)
{
    CHECK(strcmp(VIDEO_OUT_VERSION, "0.2.0-dev.1") == 0, "PS库版本不匹配");
    FakeVideo fake;
    VideoOutIo io;
    VideoOutConfig cfg;
    VideoOutStatus status;
    VideoOutAudioStatus audio_status;

    memset(&fake, 0, sizeof(fake));
    memset(&cfg, 0, sizeof(cfg));
    io.read_reg = read_reg;
    io.write_reg = write_reg;
    io.configure_vdma = configure_vdma;
    io.context = &fake;

    cfg.source = VIDEO_OUT_SOURCE_VDMA;
    cfg.format = VIDEO_OUT_PIX_XRGB8888;
    cfg.width = 320;
    cfg.height = 240;
    cfg.stride_bytes = 1280;
    cfg.scale = VIDEO_OUT_SCALE_NEAREST;
    cfg.aspect = VIDEO_OUT_ASPECT_FIT;
    cfg.enabled = 1;
    cfg.initial_frame_index = 0U;
    fake.regs[4] = 1U << 4;
    fake.busy_reads_before_clear = 3U;

    CHECK(VideoOut_Configure(&io, &cfg, 0x10000000ULL, 0U) == 0,
          "有效VDMA配置被拒绝");
    CHECK(fake.vdma_calls == 1U && fake.vdma_width == 320U &&
          fake.vdma_height == 240U && fake.vdma_bpp == 4U &&
          fake.vdma_stride == 1280U && fake.vdma_initial_frame == 0U && fake.vdma_base == 0x10000000ULL,
          "VDMA回调收到的几何参数错误");
    CHECK((fake.regs[0] & 1U) != 0U && (fake.first_ctrl_write & (1U << 8)) != 0U,
          "未写入AXI-Lite配置提交");
    CHECK(fake.ctrl_write_count == 1U && (fake.first_ctrl_write & 1U) != 0U &&
          (((fake.first_ctrl_write >> 1) & 3U) == VIDEO_OUT_SOURCE_VDMA),
          "在帧边界前切离了当前活动视频源");
    CHECK(fake.busy_on_first_vdma_call == 0U,
          "scaler仍繁忙时改动了VDMA几何参数");
    CHECK(fake.regs[1] == ((240U << 16) | 320U),
          "输入尺寸寄存器值不匹配");
    CHECK(fake.regs[7] == ((480U << 16) | 640U) &&
          fake.regs[8] == 0U && fake.regs[9] == 0U,
          "fit模式派生几何寄存器值不匹配");
    CHECK(fake.regs[10] == (320U << 16) && fake.regs[11] == (240U << 16),
          "最近邻DDA比例不匹配");

    CHECK(VideoOut_Start(&io) == 0 &&
          (fake.regs[0] & 1U) != 0U, "启动失败");
    CHECK(VideoOut_Stop(&io) == 0 &&
          (fake.regs[0] & 1U) == 0U, "停止失败");

    fake.vdma_calls = 0U;
    cfg.stride_bytes = 1000U;
    CHECK(VideoOut_Configure(&io, &cfg, 0x10000000ULL, 0U) != 0 &&
          fake.vdma_calls == 0U, "未拒绝过短的stride");

    cfg.stride_bytes = 1280U;
    cfg.width = 0U;
    CHECK(VideoOut_Configure(&io, &cfg, 0x10000000ULL, 0U) != 0,
          "未拒绝宽度为零的配置");

    cfg.width = 320U;
    cfg.height = 180U;
    cfg.stride_bytes = 1280U;
    cfg.initial_frame_index = 2U;
    fake.vdma_calls = 0U;
    CHECK(VideoOut_Configure(&io, &cfg, 0x10000000ULL, 0U) == 0,
          "320x180 fit配置被拒绝");
    CHECK(fake.regs[7] == ((360U << 16) | 640U) &&
          fake.regs[8] == (60U << 16) &&
          fake.regs[10] == (320U << 16) &&
          fake.regs[11] == (180U << 16),
          "320x180 fit几何参数或比例不匹配");
    CHECK(fake.vdma_initial_frame == 2U, "初始park帧索引未传递");

    cfg.width = 320U;
    cfg.height = 240U;
    fake.vdma_calls = 0U;
    cfg.source = VIDEO_OUT_SOURCE_BRAM;
    cfg.format = VIDEO_OUT_PIX_RGB565;
    cfg.stride_bytes = 640U;
    cfg.initial_frame_index = 0U;
    cfg.enabled = 0U;
    fake.regs[4] = 0U;
    fake.regs[12] = (240U << 16) | 320U;
    fake.regs[5] = 123U;
    fake.regs[6] = 0x20U;
    CHECK(VideoOut_Configure(&io, &cfg, 0U, 0U) == 0,
          "有效BRAM配置被拒绝");
    CHECK(fake.vdma_calls == 0U, "BRAM模式意外配置了VDMA");
    fake.regs[4] = (2U << 6) | (1U << 4); /* 当前源和忙状态 */
    CHECK(VideoOut_GetStatus(&io, &status) == 0 &&
          status.busy == 1U && status.active_width == 320U &&
          status.active_height == 240U && status.frame_count == 123U &&
          status.error_flags == 0x20U, "状态寄存器解析不匹配");

    fake.regs[13] = 1U << 1;
    CHECK(VideoOut_SetHdmiAudioEnabled(&io, 1U) == 0 && fake.regs[13] == 3U,
          "HDMI音频使能更新破坏了静音设置");
    CHECK(VideoOut_SetAudioMute(&io, 0U) == 0 && fake.regs[13] == 1U,
          "音频静音更新破坏了HDMI使能状态");
    CHECK(VideoOut_SetAudioGainQ15(&io, 24576U) == 0 && fake.regs[14] == 24576U,
          "有效Q15音频增益未写入");
    CHECK(VideoOut_SetAudioGainQ15(&io, 32769U) != 0 && fake.regs[14] == 24576U,
          "越界Q15音频增益未被拒绝");
    CHECK(VideoOut_SetHdmiAudioEnabled(&io, 2U) != 0 &&
          VideoOut_SetAudioMute(&io, 2U) != 0,
          "非法音频控制布尔值未被拒绝");
    fake.regs[15] = 7U;
    CHECK(VideoOut_GetAudioStatus(&io, &audio_status) == 0 &&
          audio_status.hdmi_audio_enabled == 1U &&
          audio_status.fifo_underflow == 1U &&
          audio_status.fifo_overflow == 1U,
          "HDMI音频状态解析不匹配");
    CHECK(VideoOut_GetAudioStatus(&io, 0) != 0,
          "未拒绝空HDMI音频状态指针");

    memset(&fake, 0, sizeof(fake));
    memset(&cfg, 0, sizeof(cfg));
    cfg.source = VIDEO_OUT_SOURCE_VDMA;
    cfg.format = VIDEO_OUT_PIX_XRGB8888;
    cfg.width = 640U;
    cfg.height = 480U;
    cfg.stride_bytes = 2560U;
    cfg.scale = VIDEO_OUT_SCALE_BYPASS;
    cfg.aspect = VIDEO_OUT_ASPECT_FIT;
    cfg.enabled = 1U;
    cfg.initial_frame_index = 0U;
    fake.regs[4] = (2U << 6) | (1U << 4) | 1U;
    fake.force_busy = 1U;
    CHECK(VideoOut_Configure(&io, &cfg, 0x18000000ULL, 4U) == 0,
          "卡住的数据流未能通过中止和重配恢复");
    CHECK(fake.abort_count == 1U && fake.resume_count == 0U &&
          fake.ctrl_write_count == 2U,
          "重配应先中止一次，再提交一次");
    CHECK(fake.hold_during_vdma == 1U && fake.busy_on_first_vdma_call == 0U,
          "输入保持且scaler空闲时VDMA回调未运行");
    CHECK((fake.last_ctrl_write & (1U << 8)) != 0U &&
          (fake.regs[4] & ((1U << 4) | (1U << 2) | (1U << 1))) == 0U &&
          (fake.regs[4] & 1U) != 0U,
          "有效提交未释放被保持的数据流");
    CHECK(VideoOut_GetStatus(&io, &status) == 0 &&
          status.enabled == 1U && status.stream_held == 0U &&
          status.config_pending == 0U,
          "状态未报告数据流已恢复");

    puts("TEST_PASS: test_video_out");
    return 0;
}
