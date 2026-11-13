#include "video_out.h"

#define REG_CTRL          0x00U
#define REG_SIZE          0x04U
#define REG_STRIDE        0x08U
#define REG_BRAM_BASE     0x0cU
#define REG_STATUS        0x10U
#define REG_FRAME_COUNT   0x14U
#define REG_ERRORS        0x18U
#define REG_ACTIVE_CFG    0x1cU
#define REG_OFFSETS       0x20U
#define REG_SOURCE_ORIGIN 0x24U
#define REG_X_RATIO       0x28U
#define REG_Y_RATIO       0x2cU
#define REG_ACTIVE_SIZE   0x30U

#define CTRL_ENABLE       (1U << 0)
#define CTRL_SOURCE_SHIFT 1U
#define CTRL_SCALE        (1U << 3)
#define CTRL_STRETCH      (1U << 4)
#define CTRL_FORMAT_SHIFT 5U
#define CTRL_COMMIT       (1U << 8)

typedef struct {
    uint16_t active_width, active_height;
    uint16_t x_offset, y_offset;
    uint16_t source_x_origin, source_y_origin;
    uint16_t x_step, x_rem, y_step, y_rem;
} VideoOutGeometry;

static uint32_t VideoOut_FormatBytes(VideoOutPixelFormat format)
{
    switch (format) {
    case VIDEO_OUT_PIX_RGB565: return 2U;
    case VIDEO_OUT_PIX_RGB888: return 3U;
    case VIDEO_OUT_PIX_XRGB8888:
    case VIDEO_OUT_PIX_BGRX8888: return 4U;
    default: return 0U;
    }
}

static int VideoOut_ValidIo(const VideoOutIo *io)
{
    return (io != 0) && (io->read_reg != 0) && (io->write_reg != 0);
}

static int VideoOut_CalcGeometry(const VideoOutConfig *config,
                                 VideoOutGeometry *geometry)
{
    uint32_t width = config->width;
    uint32_t height = config->height;
    uint32_t active_width;
    uint32_t active_height;
    uint32_t lhs;
    uint32_t rhs;

    if (config->scale == VIDEO_OUT_SCALE_BYPASS) {
        active_width = (width < VIDEO_OUT_OUTPUT_WIDTH) ? width : VIDEO_OUT_OUTPUT_WIDTH;
        active_height = (height < VIDEO_OUT_OUTPUT_HEIGHT) ? height : VIDEO_OUT_OUTPUT_HEIGHT;
        geometry->source_x_origin = (uint16_t)((width - active_width) / 2U);
        geometry->source_y_origin = (uint16_t)((height - active_height) / 2U);
    } else if (config->aspect == VIDEO_OUT_ASPECT_STRETCH) {
        active_width = VIDEO_OUT_OUTPUT_WIDTH;
        active_height = VIDEO_OUT_OUTPUT_HEIGHT;
        geometry->source_x_origin = 0U;
        geometry->source_y_origin = 0U;
    } else {
        lhs = width * VIDEO_OUT_OUTPUT_HEIGHT;
        rhs = height * VIDEO_OUT_OUTPUT_WIDTH;
        if (lhs >= rhs) {
            active_width = VIDEO_OUT_OUTPUT_WIDTH;
            active_height = (height * VIDEO_OUT_OUTPUT_WIDTH) / width;
            if (active_height == 0U) active_height = 1U;
        } else {
            active_height = VIDEO_OUT_OUTPUT_HEIGHT;
            active_width = (width * VIDEO_OUT_OUTPUT_HEIGHT) / height;
            if (active_width == 0U) active_width = 1U;
        }
        geometry->source_x_origin = 0U;
        geometry->source_y_origin = 0U;
    }

    geometry->active_width = (uint16_t)active_width;
    geometry->active_height = (uint16_t)active_height;
    geometry->x_offset = (uint16_t)((VIDEO_OUT_OUTPUT_WIDTH - active_width) / 2U);
    geometry->y_offset = (uint16_t)((VIDEO_OUT_OUTPUT_HEIGHT - active_height) / 2U);
    geometry->x_step = (uint16_t)(width / active_width);
    geometry->x_rem = (uint16_t)(width % active_width);
    geometry->y_step = (uint16_t)(height / active_height);
    geometry->y_rem = (uint16_t)(height % active_height);
    return 0;
}

int VideoOut_Configure(const VideoOutIo *io, const VideoOutConfig *config,
                       uint64_t frame0, uint32_t vdma_bytes_per_pixel)
{
    uint32_t format_bytes, control, active_cfg, offsets, origin;
    VideoOutGeometry geometry;

    if (!VideoOut_ValidIo(io) || (config == 0))
        return -1;
    if ((config->source > VIDEO_OUT_SOURCE_VDMA) ||
        (config->format > VIDEO_OUT_PIX_BGRX8888) ||
        (config->scale > VIDEO_OUT_SCALE_NEAREST) ||
        (config->aspect > VIDEO_OUT_ASPECT_STRETCH) ||
        (config->width == 0U) || (config->height == 0U) ||
        (config->width > VIDEO_OUT_MAX_INPUT_WIDTH) ||
        (config->height > VIDEO_OUT_MAX_INPUT_HEIGHT))
        return -1;

    format_bytes = VideoOut_FormatBytes(config->format);
    if ((format_bytes == 0U) ||
        (config->width > (UINT32_MAX / format_bytes)) ||
        (config->stride_bytes < ((uint32_t)config->width * format_bytes)))
        return -1;
    if (VideoOut_CalcGeometry(config, &geometry) != 0)
        return -1;

    // Wait for the current frame to retire while the active source remains
    // enabled. Switching to the default source first can stop AXI-Stream
    // mid-frame, leaving the scaler busy forever with no TLAST/SOF to recover.
    {
        uint32_t retry;
        for (retry = 0U; retry < 1000000U; ++retry) {
            if ((io->read_reg(io->context, REG_STATUS) & (1U << 4)) == 0U)
                break;
        }
        if (retry == 1000000U)
            return -1;
    }
    io->write_reg(io->context, REG_SIZE,
                  ((uint32_t)config->height << 16) | config->width);
    io->write_reg(io->context, REG_STRIDE, config->stride_bytes);
    io->write_reg(io->context, REG_BRAM_BASE, (uint32_t)frame0);

    active_cfg = ((uint32_t)geometry.active_height << 16) | geometry.active_width;
    offsets = ((uint32_t)geometry.y_offset << 16) | geometry.x_offset;
    origin = ((uint32_t)geometry.source_y_origin << 16) | geometry.source_x_origin;
    io->write_reg(io->context, REG_ACTIVE_CFG, active_cfg);
    io->write_reg(io->context, REG_OFFSETS, offsets);
    io->write_reg(io->context, REG_SOURCE_ORIGIN, origin);
    io->write_reg(io->context, REG_X_RATIO,
                  ((uint32_t)geometry.x_rem << 16) | geometry.x_step);
    io->write_reg(io->context, REG_Y_RATIO,
                  ((uint32_t)geometry.y_rem << 16) | geometry.y_step);

    control = ((uint32_t)config->source << CTRL_SOURCE_SHIFT) |
              ((uint32_t)config->format << CTRL_FORMAT_SHIFT);
    if (config->scale == VIDEO_OUT_SCALE_NEAREST) control |= CTRL_SCALE;
    if (config->aspect == VIDEO_OUT_ASPECT_STRETCH) control |= CTRL_STRETCH;

    // The callback configures the standard AXI VDMA; it does not own the core registers.
    if (config->source == VIDEO_OUT_SOURCE_VDMA) {
        if (io->configure_vdma == 0) return -1;
        if (vdma_bytes_per_pixel == 0U) vdma_bytes_per_pixel = format_bytes;
        // V1 VDMA stream width is 32 bits: one padded RGB pixel per beat.
        if ((vdma_bytes_per_pixel != 4U) ||
            (config->format == VIDEO_OUT_PIX_RGB565)) return -1;
        if (config->stride_bytes < ((uint32_t)config->width * vdma_bytes_per_pixel))
            return -1;
        if (io->configure_vdma(io->context, frame0, config->width,
                               config->height, vdma_bytes_per_pixel,
                               config->stride_bytes,
                               config->initial_frame_index) != 0) return -1;
    }

    if (config->enabled != 0U) control |= CTRL_ENABLE;
    io->write_reg(io->context, REG_CTRL, control | CTRL_COMMIT);
    return 0;
}

int VideoOut_Start(const VideoOutIo *io)
{
    uint32_t control;
    if (!VideoOut_ValidIo(io)) return -1;
    control = io->read_reg(io->context, REG_CTRL);
    control = (control | CTRL_ENABLE) & ~CTRL_COMMIT;
    if (((control >> CTRL_SOURCE_SHIFT) & 3U) == VIDEO_OUT_SOURCE_BRAM)
        control |= (1U << 9);
    io->write_reg(io->context, REG_CTRL, control | CTRL_COMMIT);
    return 0;
}

int VideoOut_BramSubmit(const VideoOutIo *io, uint32_t frame_base_word)
{
    uint32_t control;
    if (!VideoOut_ValidIo(io))
        return -1;
    control = io->read_reg(io->context, REG_CTRL);
    if (((control >> CTRL_SOURCE_SHIFT) & 3U) != VIDEO_OUT_SOURCE_BRAM)
        return -1;
    io->write_reg(io->context, REG_BRAM_BASE, frame_base_word);
    control = (control & ~CTRL_COMMIT) | (1U << 9);
    io->write_reg(io->context, REG_CTRL, control);
    return 0;
}

int VideoOut_Stop(const VideoOutIo *io)
{
    uint32_t control;
    if (!VideoOut_ValidIo(io)) return -1;
    control = io->read_reg(io->context, REG_CTRL);
    control = (control & ~CTRL_ENABLE) & ~CTRL_COMMIT;
    io->write_reg(io->context, REG_CTRL, control | CTRL_COMMIT);
    return 0;
}

int VideoOut_GetStatus(const VideoOutIo *io, VideoOutStatus *status)
{
    uint32_t state, active_size;
    if (!VideoOut_ValidIo(io) || (status == 0)) return -1;
    state = io->read_reg(io->context, REG_STATUS);
    active_size = io->read_reg(io->context, REG_ACTIVE_SIZE);
    status->busy = (uint8_t)((state >> 4) & 1U);
    status->active_source = (state >> 6) & 3U;
    status->active_width = active_size & 0x3ffU;
    status->active_height = (active_size >> 16) & 0x3ffU;
    status->frame_count = io->read_reg(io->context, REG_FRAME_COUNT);
    status->error_flags = io->read_reg(io->context, REG_ERRORS);
    return 0;
}
