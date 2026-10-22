#include "expp.hpp"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <erl_nif.h>
#include <jpeglib.h>
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/resizable_parallel_runner.h>
#include <jxl/resizable_parallel_runner_cxx.h>
#include <jxl/thread_parallel_runner.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <memory>
#include <mutex>
#include <png.h>
#include <poppler/cpp/poppler-document.h>
#include <poppler/cpp/poppler-page-renderer.h>
#include <poppler/cpp/poppler-page.h>
#include <poppler/cpp/poppler-version.h>
#include <sstream>
#include <stdio.h>
#include <tiffio.h>
#include <tiffio.hxx>
#include <tuple>
#include <vector>
#include <webp/decode.h>
#include <webp/encode.h>

using namespace std;
using namespace expp;

using text_chunk_t = std::tuple<string, string, string, string>;
using text_chunks_t = std::vector<text_chunk_t>;

struct decompress_result_t
{
    binary pixels;
    uint32_t width;
    uint32_t height;
    uint32_t channels;
    uint32_t bit_depth;
    optional<binary> exif;
    text_chunks_t text_chunks;
    std::vector<binary> xml_boxes;
    std::vector<binary> jumb_boxes;
};


namespace expp
{
template <>
struct type_cast<decompress_result_t>
{
    static ERL_NIF_TERM to_term(ErlNifEnv* env, const decompress_result_t& result) noexcept
    {
        return enif_make_tuple9(
            env,
            type_cast<binary>::to_term(env, result.pixels),
            type_cast<uint32_t>::to_term(env, result.width),
            type_cast<uint32_t>::to_term(env, result.height),
            type_cast<uint32_t>::to_term(env, result.channels),
            type_cast<uint32_t>::to_term(env, result.bit_depth),
            type_cast<optional<binary>>::to_term(env, result.exif),
            type_cast<text_chunks_t>::to_term(env, result.text_chunks),
            type_cast<std::vector<binary>>::to_term(env, result.xml_boxes),
            type_cast<std::vector<binary>>::to_term(env, result.jumb_boxes));
    }
};
}  // namespace expp


// Decoders check image dimensions against a caller-given limit before allocating, so a small file
// cannot claim a huge image. A limit of 0 means none.
static bool exceeds_max_pixels(uint64_t width, uint64_t height, uint64_t max_pixels)
{
    return max_pixels != 0 && width * height > max_pixels;
}

constexpr string_view MAX_PIXELS_ERROR = "image has more pixels than max_pixels allows";


// Destroys a libjpeg compress or decompress struct when the scope exits.
struct jpeg_guard
{
    j_common_ptr cinfo;
    ~jpeg_guard()
    {
        jpeg_destroy(cinfo);
    }
};


void jpeg_error_exit(j_common_ptr cinfo)
{
    char error_message[JMSG_LENGTH_MAX];
    (*(cinfo->err->format_message))(cinfo, error_message);
    throw erl_error<string>(error_message);
}


yielding<expected<decompress_result_t, string>> jpeg_decompress(std::vector<uint8_t> jpeg_bytes, uint64_t max_pixels)
{
    struct jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;
    yielding_timer timer;

    // create decompressor
    cinfo.err = jpeg_std_error(&err);
    err.error_exit = jpeg_error_exit;
    jpeg_create_decompress(&cinfo);
    jpeg_guard guard{reinterpret_cast<j_common_ptr>(&cinfo)};
    cinfo.do_fancy_upsampling = FALSE;

    // set source buffer
    jpeg_mem_src(&cinfo, jpeg_bytes.data(), jpeg_bytes.size());

    // read jpeg header
    jpeg_read_header(&cinfo, TRUE);
    if (cinfo.jpeg_color_space == JCS_CMYK || cinfo.jpeg_color_space == JCS_YCCK)
    {
        co_yield std::unexpected("CMYK JPEG images are not supported");
        co_return;
    }
    if (exceeds_max_pixels(cinfo.image_width, cinfo.image_height, max_pixels))
    {
        co_yield std::unexpected(string(MAX_PIXELS_ERROR));
        co_return;
    }

    // decompress
    jpeg_start_decompress(&cinfo);

    const uint32_t out_width = cinfo.output_width;
    const uint32_t out_height = cinfo.output_height;
    const uint32_t num_components = static_cast<uint32_t>(cinfo.output_components);

    const size_t row_stride = static_cast<size_t>(out_width) * num_components;
    binary output(row_stride * out_height);

    // read scanlines
    while (cinfo.output_scanline < cinfo.output_height)
    {
        auto row_ptr = output.data + cinfo.output_scanline * row_stride;
        jpeg_read_scanlines(&cinfo, &row_ptr, 1);

        if (timer.times_up())
        {
            co_yield nullopt;
            timer.reset();
        }
    }

    jpeg_finish_decompress(&cinfo);

    co_yield decompress_result_t{
        .pixels = std::move(output),
        .width = out_width,
        .height = out_height,
        .channels = num_components,
        .bit_depth = 8u,
    };
}


yielding<expected<binary, string>> jpeg_compress(
    vector<uint8_t> pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    int quality,
    optional<tuple<uint8_t, uint16_t, uint16_t>> jfif_density,
    vector<vector<uint8_t>> app1_segments)
{
    struct jpeg_error_mgr err;
    struct jpeg_compress_struct cinfo;
    yielding_timer timer;

    // create the compressor
    cinfo.err = jpeg_std_error(&err);
    err.error_exit = jpeg_error_exit;
    jpeg_create_compress(&cinfo);
    jpeg_guard guard{reinterpret_cast<j_common_ptr>(&cinfo)};

    // jpeg_mem_dest mallocs the output buffer; the caller frees it, including on error.
    uint8_t* buf = nullptr;
    unsigned long outsize = 0;
    std::unique_ptr<uint8_t*, decltype([](uint8_t** p) { free(*p); })> buf_guard(&buf);
    jpeg_mem_dest(&cinfo, &buf, &outsize);

    cinfo.image_width = width;
    cinfo.image_height = height;
    cinfo.input_components = channels;
    cinfo.in_color_space = channels == 1 ? JCS_GRAYSCALE : JCS_RGB;

    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, quality, TRUE);
    if (jfif_density.has_value())
        std::tie(cinfo.density_unit, cinfo.X_density, cinfo.Y_density) = jfif_density.value();

    // do the actual compression
    jpeg_start_compress(&cinfo, TRUE);

    for (const auto& segment : app1_segments)
        jpeg_write_marker(&cinfo, JPEG_APP0 + 1, segment.data(), static_cast<unsigned int>(segment.size()));

    while (cinfo.next_scanline < cinfo.image_height)
    {
        auto row = pixels.data() + cinfo.next_scanline * channels * width;
        jpeg_write_scanlines(&cinfo, &row, 1);

        if (timer.times_up())
        {
            co_yield nullopt;
            timer.reset();
        }
    }
    jpeg_finish_compress(&cinfo);

    co_yield binary::from_bytes(buf, outsize);
}


struct png_read_binary
{
    const vector<uint8_t>& data;
    size_t offset = 8;

    void read(png_structp png_ptr, png_bytep dest, png_size_t size_to_read)
    {
        if (size_to_read > this->data.size() - this->offset)
            png_error(png_ptr, "unexpected end of png data");
        std::copy_n(this->data.data() + offset, size_to_read, dest);
        this->offset += size_to_read;
    }
};


void png_error_exit(png_structp png_ptr, const char* error_message)
{
    throw erl_error<string>(error_message);
}


// Destroys libpng read structs when the scope exits.
struct png_read_guard
{
    png_structp png_ptr;
    png_infop info_ptr = nullptr;
    ~png_read_guard()
    {
        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
    }
};


// Destroys libpng write structs when the scope exits.
struct png_write_guard
{
    png_structp png_ptr;
    png_infop info_ptr = nullptr;
    ~png_write_guard()
    {
        png_destroy_write_struct(&png_ptr, &info_ptr);
    }
};


yielding<expected<decompress_result_t, string_view>> png_decompress(vector<uint8_t> png_bytes, uint64_t max_pixels)
{
    yielding_timer timer;

    // check png signature
    if (png_bytes.size() < 8 || png_sig_cmp(png_bytes.data(), 0, 8))
    {
        co_yield std::unexpected("invalid png header");
        co_return;
    }

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield std::unexpected("couldn't initialize png read struct");
        co_return;
    }
    png_read_guard guard{png_ptr};

    png_infop info_ptr = guard.info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        co_yield std::unexpected("couldn't initialize png info struct");
        co_return;
    }

    // read metadata
    png_read_binary data_wrapper{png_bytes};
    png_set_read_fn(
        png_ptr,
        reinterpret_cast<png_voidp>(&data_wrapper),
        [](png_structp png_ptr, png_bytep dest, png_size_t size_to_read) {
            auto data_wrapper = reinterpret_cast<png_read_binary*>(png_get_io_ptr(png_ptr));
            data_wrapper->read(png_ptr, dest, size_to_read);
        });
    png_set_sig_bytes(png_ptr, 8);
    png_read_info(png_ptr, info_ptr);

    const png_uint_32 width = png_get_image_width(png_ptr, info_ptr);
    const png_uint_32 height = png_get_image_height(png_ptr, info_ptr);
    if (exceeds_max_pixels(width, height, max_pixels))
    {
        co_yield std::unexpected(MAX_PIXELS_ERROR);
        co_return;
    }
    const png_uint_32 source_bit_depth = png_get_bit_depth(png_ptr, info_ptr);
    const png_uint_32 color_type = png_get_color_type(png_ptr, info_ptr);

    switch (color_type)
    {
    case PNG_COLOR_TYPE_PALETTE:  // convert palette to RGB
        png_set_palette_to_rgb(png_ptr);
        break;
    case PNG_COLOR_TYPE_GRAY:  // expand 1, 2, or 4 bit grayscale to 8 bit grayscale
        if (source_bit_depth < 8)
            png_set_expand_gray_1_2_4_to_8(png_ptr);
        break;
    }

    // Palette images get tRNS expanded above; for grayscale and RGB it marks one transparent color.
    if (color_type != PNG_COLOR_TYPE_PALETTE && png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS))
        png_set_tRNS_to_alpha(png_ptr);

    if constexpr (std::endian::native == std::endian::little)
    {
        if (source_bit_depth == 16)
            png_set_swap(png_ptr);
    }

    const int num_passes = png_set_interlace_handling(png_ptr);
    // Palette/transparency and packed-bit expansion change the output layout.
    png_read_update_info(png_ptr, info_ptr);

    const png_uint_32 bit_depth = png_get_bit_depth(png_ptr, info_ptr);
    const png_uint_32 channels = png_get_channels(png_ptr, info_ptr);
    const size_t stride = png_get_rowbytes(png_ptr, info_ptr);
    binary output(height * stride);

    // Depending on whether the image is interlaced, we need to decode multiple passes
    // See https://github.com/glennrp/libpng/blob/libpng16/libpng-manual.txt and
    // libpng png_read_image's implementation
    // Adam7 passes update the same output rows in place.
    for (int pass = 0; pass < num_passes; pass++)
    {
        for (size_t i = 0; i < height; i++)
        {
            png_read_row(png_ptr, reinterpret_cast<png_bytep>(output.data) + i * stride, nullptr);

            if (timer.times_up())
            {
                co_yield nullopt;
                timer.reset();
            }
        }
    }

    // Read the chunks after the image data, which may hold metadata, and check the file is complete.
    png_read_end(png_ptr, info_ptr);

    // read the exif data
    optional<binary> exif_data = nullopt;
    {
        png_bytep exif = nullptr;
        png_uint_32 exif_length;
        if (png_get_eXIf_1(png_ptr, info_ptr, &exif_length, &exif) != 0)
        {
            if (exif_length > 0)
                exif_data = binary::from_bytes(exif, exif_length);
        }
    }

    // read tEXt/iTxt/zTXt data
    text_chunks_t text_data;
    {
        png_textp text_ptr = nullptr;
        const int num_text = png_get_text(png_ptr, info_ptr, &text_ptr, nullptr);
        for (int i = 0; i < num_text; i++)
        {
            const png_text& text = text_ptr[i];
            const bool is_itxt =
                text.compression == PNG_ITXT_COMPRESSION_NONE || text.compression == PNG_ITXT_COMPRESSION_zTXt;
            text_data.emplace_back(
                text.key,
                string(text.text, is_itxt ? text.itxt_length : text.text_length),
                text.lang != nullptr ? text.lang : "",
                text.lang_key != nullptr ? text.lang_key : "");
        }
    }

    co_yield decompress_result_t{
        .pixels = std::move(output),
        .width = width,
        .height = height,
        .channels = channels,
        .bit_depth = bit_depth,
        .exif = std::move(exif_data),
        .text_chunks = std::move(text_data),
    };
}


yielding<expected<vector<png_byte>, string_view>> png_compress(
    vector<uint8_t> pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    optional<vector<uint8_t>> exif,
    text_chunks_t text_chunks)
{
    yielding_timer timer;

    int color_type;
    switch (channels)
    {
    case 1:
        color_type = PNG_COLOR_TYPE_GRAY;
        break;
    case 2:
        color_type = PNG_COLOR_TYPE_GRAY_ALPHA;
        break;
    case 3:
        color_type = PNG_COLOR_TYPE_RGB;
        break;
    case 4:
        color_type = PNG_COLOR_TYPE_RGB_ALPHA;
        break;
    default:
        co_yield std::unexpected("unsupported number of channels (must be 1-4)");
        co_return;
    }

    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield std::unexpected("couldn't initialize png write struct");
        co_return;
    }
    png_write_guard guard{png_ptr};

    png_infop info_ptr = guard.info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        co_yield std::unexpected("couldn't initialize png info struct");
        co_return;
    }

    // set up the output data, as well as the callback to write into that data
    vector<png_byte> out_data;
    auto png_chunk_producer = [](png_structp png_ptr, png_bytep data, png_size_t length) {
        auto out_data_p = reinterpret_cast<vector<png_byte>*>(png_get_io_ptr(png_ptr));
        std::copy_n(data, length, std::back_inserter(*out_data_p));
    };
    png_set_write_fn(png_ptr, &out_data, png_chunk_producer, nullptr);

    png_set_IHDR(
        png_ptr,
        info_ptr,
        width,
        height,
        bit_depth,
        color_type,
        PNG_INTERLACE_NONE,
        PNG_COMPRESSION_TYPE_BASE,
        PNG_FILTER_TYPE_BASE);

    if (exif.has_value())
        png_set_eXIf_1(png_ptr, info_ptr, exif->size(), exif->data());

    if (!text_chunks.empty())
    {
        // libpng copies the text, so the entries can point into text_chunks.
        vector<png_text> png_text_entries;
        for (auto& [key, value, language_tag, translated_keyword] : text_chunks)
        {
            png_text entry = {};
            entry.compression = PNG_ITXT_COMPRESSION_NONE;
            entry.key = key.data();
            entry.text = value.data();
            entry.text_length = value.size();
            entry.itxt_length = value.size();
            entry.lang = language_tag.data();
            entry.lang_key = translated_keyword.data();
            png_text_entries.push_back(entry);
        }

        png_set_text(png_ptr, info_ptr, png_text_entries.data(), png_text_entries.size());
    }

    png_write_info(png_ptr, info_ptr);

    if constexpr (std::endian::native == std::endian::little)
    {
        if (bit_depth == 16)
            png_set_swap(png_ptr);
    }

    // write the pixels
    const size_t stride = static_cast<size_t>(width) * channels * bit_depth / 8;
    for (size_t i = 0; i < height; i++)
    {
        png_write_row(png_ptr, pixels.data() + i * stride);

        if (timer.times_up())
        {
            co_yield nullopt;
            timer.reset();
        }
    }

    png_write_end(png_ptr, nullptr);

    co_yield std::move(out_data);
}


static_assert(JXL_ENC_SUCCESS == 0 && JXL_DEC_SUCCESS == 0);

// NOTE: This macro uses `return`, NOT `co_return`. It is NOT safe to use inside coroutines.
#define JXL_ENSURE_SUCCESS(func, ...)                                                                                  \
    if (func(__VA_ARGS__) != 0)                                                                                        \
    {                                                                                                                  \
        return std::unexpected(#func " failed");                                                                       \
    }


// Parse JXL EXIF box data, handling the 4-byte big-endian offset prefix.
static optional<binary> parse_jxl_exif(const vector<uint8_t>& exif_data)
{
    if (exif_data.size() < 4)
        return nullopt;

    // The first 4 bytes are a big-endian offset (usually 0)
    size_t offset = static_cast<size_t>(exif_data[0]) << 24 | static_cast<size_t>(exif_data[1]) << 16 |
                    static_cast<size_t>(exif_data[2]) << 8 | static_cast<size_t>(exif_data[3]);

    if (4 + offset >= exif_data.size())
        return nullopt;

    return binary::from_bytes(exif_data.data() + 4 + offset, exif_data.size() - 4 - offset);
}


// Collect all output from a JXL encoder into a vector.
static expected<vector<uint8_t>, string_view> jxl_collect_compressed(JxlEncoder* enc)
{
    vector<uint8_t> compressed(64);
    uint8_t* next_out = compressed.data();
    size_t avail_out = compressed.size();
    JxlEncoderStatus process_result;
    while (true)
    {
        process_result = JxlEncoderProcessOutput(enc, &next_out, &avail_out);
        if (process_result != JXL_ENC_NEED_MORE_OUTPUT)
            break;
        size_t offset = next_out - compressed.data();
        compressed.resize(compressed.size() * 2);
        next_out = compressed.data() + offset;
        avail_out = compressed.size() - offset;
    }
    compressed.resize(next_out - compressed.data());
    if (process_result != JXL_ENC_SUCCESS)
        return std::unexpected("JxlEncoderProcessOutput failed");

    return compressed;
}


expected<decompress_result_t, string_view> jxl_decompress(const binary& jxl_bytes, uint64_t max_pixels)
{
    // Multi-threaded parallel runner.
    auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE | JXL_DEC_BOX);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());
    JXL_ENSURE_SUCCESS(JxlDecoderSetDecompressBoxes, dec.get(), JXL_TRUE);
    JXL_ENSURE_SUCCESS(JxlDecoderSetInput, dec.get(), jxl_bytes.data, jxl_bytes.size);
    JxlDecoderCloseInput(dec.get());

    decompress_result_t result{};
    const constexpr size_t chunk_size = 0xffff;
    string box_type;  // type of the metadata box being collected, empty if none
    vector<uint8_t> box_data;

    auto finish_box = [&]() {
        if (box_type.empty())
            return;

        box_data.resize(box_data.size() - JxlDecoderReleaseBoxBuffer(dec.get()));
        if (box_type == "Exif")
        {
            // A malformed Exif box is skipped, like malformed EXIF data.
            if (optional<binary> exif = parse_jxl_exif(box_data))
                result.exif = std::move(exif.value());
        }
        else
        {
            auto& boxes = box_type == "xml " ? result.xml_boxes : result.jumb_boxes;
            boxes.push_back(binary::from_bytes(box_data.data(), box_data.size()));
        }

        box_type.clear();
    };

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return std::unexpected("Decoder error");
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return std::unexpected("truncated JXL data");
        }
        else if (status == JXL_DEC_BASIC_INFO)
        {
            JxlBasicInfo info;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBasicInfo, dec.get(), &info);

            if (info.exponent_bits_per_sample != 0)
                return std::unexpected("floating-point JXL images are not supported");
            if (info.bits_per_sample > 16)
                return std::unexpected("JXL images with more than 16 bits per sample are not supported");
            if (exceeds_max_pixels(info.xsize, info.ysize, max_pixels))
                return std::unexpected(MAX_PIXELS_ERROR);

            JxlResizableParallelRunnerSetThreads(
                runner.get(), JxlResizableParallelRunnerSuggestThreads(info.xsize, info.ysize));
            result.width = info.xsize;
            result.height = info.ysize;
            result.channels = info.num_color_channels + info.num_extra_channels;
            // libjxl scales other integer depths (e.g. 10 or 12 bits) to the full output range.
            result.bit_depth = info.bits_per_sample <= 8 ? 8 : 16;
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            const JxlDataType data_type = result.bit_depth == 8 ? JXL_TYPE_UINT8 : JXL_TYPE_UINT16;
            JxlPixelFormat format = {result.channels, data_type, JXL_NATIVE_ENDIAN, 0};

            size_t buffer_size;
            JXL_ENSURE_SUCCESS(JxlDecoderImageOutBufferSize, dec.get(), &format, &buffer_size);
            if (buffer_size !=
                static_cast<size_t>(result.width) * result.height * result.channels * result.bit_depth / 8)
                return std::unexpected("Invalid out buffer size");
            result.pixels = binary{buffer_size};
            JXL_ENSURE_SUCCESS(JxlDecoderSetImageOutBuffer, dec.get(), &format, result.pixels.data, result.pixels.size);
        }
        else if (status == JXL_DEC_BOX)
        {
            finish_box();

            JxlBoxType type;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBoxType, dec.get(), type, JXL_TRUE);
            const string_view type_view(type, 4);
            if (type_view != "Exif" && type_view != "xml " && type_view != "jumb")
                continue;

            box_type = type_view;
            box_data.resize(chunk_size);
            JXL_ENSURE_SUCCESS(JxlDecoderSetBoxBuffer, dec.get(), box_data.data(), box_data.size());
        }
        else if (status == JXL_DEC_BOX_NEED_MORE_OUTPUT)
        {
            const size_t remaining = JxlDecoderReleaseBoxBuffer(dec.get());
            const size_t output_pos = box_data.size() - remaining;
            box_data.resize(box_data.size() + chunk_size);
            JXL_ENSURE_SUCCESS(
                JxlDecoderSetBoxBuffer, dec.get(), box_data.data() + output_pos, box_data.size() - output_pos);
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // Nothing to do. Do not yet return. If the image is an animation, more
            // full frames may be decoded. This only keeps the last one.
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            finish_box();
            return result;
        }
        else
        {
            return std::unexpected("unexpected JXL decoder status");
        }
    }
}


expected<vector<uint8_t>, string_view> jxl_compress(
    const binary& pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    vector<pair<string, binary>> jxl_boxes,
    double distance,
    bool lossless,
    int effort,
    int progressive,
    int order,
    int orientation)
{
    auto runner = JxlThreadParallelRunnerMake(
        /*memory_manager=*/nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());

    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetParallelRunner, enc.get(), JxlThreadParallelRunner, runner.get());

    if (!jxl_boxes.empty())
        JXL_ENSURE_SUCCESS(JxlEncoderUseBoxes, enc.get());

    JxlPixelFormat pixel_format = {channels, bit_depth == 16 ? JXL_TYPE_UINT16 : JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    const bool is_grayscale = channels < 3;
    const bool has_alpha = channels == 2 || channels == 4;

    JxlBasicInfo basic_info;
    JxlEncoderInitBasicInfo(&basic_info);
    basic_info.xsize = width;
    basic_info.ysize = height;
    basic_info.bits_per_sample = bit_depth;
    basic_info.num_color_channels = is_grayscale ? 1 : 3;
    if (has_alpha)
    {
        basic_info.alpha_bits = bit_depth;
        basic_info.num_extra_channels = 1;
    }
    basic_info.uses_original_profile = lossless;
    basic_info.orientation = static_cast<JxlOrientation>(orientation);
    JXL_ENSURE_SUCCESS(JxlEncoderSetBasicInfo, enc.get(), &basic_info);

    JxlColorEncoding color_encoding = {};
    JxlColorEncodingSetToSRGB(&color_encoding, is_grayscale);
    JXL_ENSURE_SUCCESS(JxlEncoderSetColorEncoding, enc.get(), &color_encoding);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameLossless, encoder_options, lossless);
    JXL_ENSURE_SUCCESS(JxlEncoderSetFrameDistance, encoder_options, distance);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);

    if (progressive > 0)
    {
        JXL_ENSURE_SUCCESS(
            JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_PROGRESSIVE_DC, progressive);
        JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_PROGRESSIVE_AC, 1);
    }

    if (order > 0)
    {
        JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_GROUP_ORDER, order);
    }

    for (const auto& [box_type, box_contents] : jxl_boxes)
    {
        if (box_type.size() != 4)
            return std::unexpected("JXL box types must be 4 bytes");

        JXL_ENSURE_SUCCESS(
            JxlEncoderAddBox, enc.get(), box_type.data(), box_contents.data, box_contents.size, JXL_FALSE);
    }

    JXL_ENSURE_SUCCESS(JxlEncoderAddImageFrame, encoder_options, &pixel_format, pixels.data, pixels.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view> jxl_transcode_from_jpeg(
    const binary& jpeg_bytes, int effort, bool store_jpeg_metadata)
{
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);

    JXL_ENSURE_SUCCESS(JxlEncoderUseContainer, enc.get(), JXL_TRUE);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), store_jpeg_metadata);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JXL_ENSURE_SUCCESS(JxlEncoderAddJPEGFrame, encoder_options, jpeg_bytes.data, jpeg_bytes.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view> jxl_transcode_to_jpeg(const binary& jxl_bytes)
{
    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_FULL_IMAGE | JXL_DEC_JPEG_RECONSTRUCTION);

    JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);

    vector<uint8_t> jpeg_bytes;

    for (;;)
    {
        JxlDecoderStatus status = JxlDecoderProcessInput(dec.get());

        if (status == JXL_DEC_ERROR)
        {
            return std::unexpected("Decoder error");
        }
        else if (status == JXL_DEC_NEED_MORE_INPUT)
        {
            return std::unexpected("Error, already provided all input");
        }
        else if (status == JXL_DEC_JPEG_RECONSTRUCTION)
        {
            jpeg_bytes.resize(static_cast<size_t>(jxl_bytes.size * 1.5));
            JxlDecoderSetJPEGBuffer(dec.get(), jpeg_bytes.data(), jpeg_bytes.size());
        }
        else if (status == JXL_DEC_JPEG_NEED_MORE_OUTPUT)
        {
            const size_t existing_size = jpeg_bytes.size();
            jpeg_bytes.resize(static_cast<size_t>(existing_size * 1.5));
            const size_t bytes_unwritten = JxlDecoderReleaseJPEGBuffer(dec.get());
            const size_t bytes_already_written = existing_size - bytes_unwritten;
            if (bytes_already_written != 0)
                return std::unexpected("JXL JPEG transcode: unexpected partial write after buffer resize");
            JxlDecoderSetJPEGBuffer(dec.get(), jpeg_bytes.data(), jpeg_bytes.size());
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // resize the vector back to the written size
            const size_t bytes_unwritten = JxlDecoderReleaseJPEGBuffer(dec.get());
            jpeg_bytes.resize(jpeg_bytes.size() - bytes_unwritten);
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            // All decoding successfully finished.
            return jpeg_bytes;
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            return std::unexpected("Cannot transcode to JPEG: image was not originally transcoded from JPEG");
        }
        else
        {
            return std::unexpected("unexpected JXL decoder status");
        }
    }
}


struct TIFFWrapper
{
    TIFF* tiff;
    unique_ptr<stringstream> sstream;
    // libtiff handles are not thread-safe, and pages may be rendered from several processes at once.
    std::mutex mutex;

    TIFFWrapper(TIFF* tiff, unique_ptr<stringstream> sstream) :
        tiff(tiff),
        sstream(std::move(sstream))
    {}

    ~TIFFWrapper()
    {
        TIFFClose(this->tiff);
    }
};


typedef resource<std::unique_ptr<poppler::document>> pdf_resource_t;


expected<tuple<pdf_resource_t, int>, string_view> pdf_load_document(binary bytes)
{
    // load document from bytes and check for errors
    vector<char> buf(bytes.data, bytes.data + bytes.size);
    unique_ptr<poppler::document> document(poppler::document::load_from_data(&buf));
    if (!document)
        return std::unexpected("invalid pdf file");
    if (document->is_locked())
        return std::unexpected("document is locked");

    const auto num_pages = document->pages();
    return make_tuple(pdf_resource_t::alloc(std::move(document)), num_pages);
}


expected<decompress_result_t, string_view> pdf_render_page(
    pdf_resource_t document_resource, int page_idx, int dpi, uint64_t max_pixels)
{
    auto& document = document_resource.get();
    if (page_idx < 0 || page_idx >= document->pages())
        return std::unexpected("page index out of range");

    unique_ptr<poppler::page> page(document->create_page(page_idx));
    // Page sizes are in points, 72 per inch. Round up, in floating point, so a fractional or huge
    // page cannot slip under the limit.
    const auto rect = page->page_rect();
    const double page_pixels = std::ceil(rect.width() * dpi / 72) * std::ceil(rect.height() * dpi / 72);
    if (max_pixels != 0 && page_pixels > static_cast<double>(max_pixels))
        return std::unexpected(MAX_PIXELS_ERROR);
    poppler::page_renderer renderer;
    renderer.set_render_hints(
        poppler::page_renderer::antialiasing | poppler::page_renderer::text_antialiasing |
        poppler::page_renderer::text_hinting);
    auto image = renderer.render_page(page.get(), dpi, dpi);
    if (!image.is_valid())
        return std::unexpected("failed to render a valid image");

    uint32_t height = image.height();
    uint32_t width = image.width();
    binary pixels = binary::from_bytes(image.data(), height * image.bytes_per_row());
    uint32_t channels = image.bytes_per_row() / width;

    const auto format = image.format();
    if (format == poppler::image::format_invalid)
        return std::unexpected("Invalid image format");
    else if (format == poppler::image::format_mono)
        return std::unexpected("Mono images not supported right now");
    else if (format == poppler::image::format_bgr24 || format == poppler::image::format_argb32)
    {
        // convert bgr to rgb
        for (uint32_t i = 0; i < pixels.size; i += channels)
            std::swap(pixels.data[i], pixels.data[i + 2]);
    }

    return decompress_result_t{
        .pixels = std::move(pixels),
        .width = width,
        .height = height,
        .channels = channels,
        .bit_depth = 8u,
    };
}

typedef resource<TIFFWrapper> tiff_resource_t;

expected<tuple<tiff_resource_t, int>, string_view> tiff_load_document(binary bytes)
{
    // load document from bytes and check for errors
    auto sstream = make_unique<stringstream>();
    sstream->write(reinterpret_cast<char*>(bytes.data), bytes.size);
    auto document = TIFFStreamOpen("file.tiff", reinterpret_cast<std::istream*>(sstream.get()));
    if (!document)
        return std::unexpected("invalid tiff file");

    int num_pages = 0;
    do
    {
        num_pages++;
    } while (TIFFReadDirectory(document));

    return make_tuple(tiff_resource_t::alloc(document, std::move(sstream)), num_pages);
}


expected<decompress_result_t, string_view> tiff_render_page(
    tiff_resource_t document_resource, int page_index, uint64_t max_pixels)
{
    auto& wrapper = document_resource.get();
    std::lock_guard lock(wrapper.mutex);
    TIFF* document = wrapper.tiff;

    if (!TIFFSetDirectory(document, page_index))
        return std::unexpected("failed to set TIFF directory");

    int width = 0, height = 0;
    if (!TIFFGetField(document, TIFFTAG_IMAGEWIDTH, &width))
        return std::unexpected("failed to read TIFF image width");
    if (!TIFFGetField(document, TIFFTAG_IMAGELENGTH, &height))
        return std::unexpected("failed to read TIFF image height");
    if (width <= 0 || height <= 0)
        return std::unexpected("invalid TIFF image dimensions");
    if (exceeds_max_pixels(width, height, max_pixels))
        return std::unexpected(MAX_PIXELS_ERROR);

    uint16_t orientation = ORIENTATION_TOPLEFT;
    TIFFGetFieldDefaulted(document, TIFFTAG_ORIENTATION, &orientation);
    if (orientation < ORIENTATION_TOPLEFT || orientation > ORIENTATION_LEFTBOT)
        orientation = ORIENTATION_TOPLEFT;

    // Requesting the file's own orientation reads the rows as stored. libtiff only flips, never
    // transposes, so all orientations are applied below.
    binary pixels{static_cast<size_t>(width) * height * 4};
    if (!TIFFReadRGBAImageOriented(document, width, height, reinterpret_cast<uint32_t*>(pixels.data), orientation, 0))
        return std::unexpected("failed to read TIFF image");

    if (orientation == ORIENTATION_TOPLEFT)
        return decompress_result_t{
            .pixels = std::move(pixels),
            .width = static_cast<uint32_t>(width),
            .height = static_cast<uint32_t>(height),
            .channels = 4u,
            .bit_depth = 8u,
        };

    const bool transposed = orientation >= ORIENTATION_LEFTTOP;
    const size_t w = width, h = height, out_width = transposed ? h : w;
    binary upright{pixels.size};
    const auto stored = reinterpret_cast<const uint32_t*>(pixels.data);
    auto out = reinterpret_cast<uint32_t*>(upright.data);
    for (size_t r = 0; r < h; r++)
    {
        for (size_t c = 0; c < w; c++)
        {
            // where the stored pixel (r, c) lands, per the TIFF/EXIF orientation semantics
            auto [i, j] = [&]() -> pair<size_t, size_t> {
                switch (orientation)
                {
                case ORIENTATION_TOPRIGHT:
                    return {r, w - 1 - c};
                case ORIENTATION_BOTRIGHT:
                    return {h - 1 - r, w - 1 - c};
                case ORIENTATION_BOTLEFT:
                    return {h - 1 - r, c};
                case ORIENTATION_LEFTTOP:
                    return {c, r};
                case ORIENTATION_RIGHTTOP:
                    return {c, h - 1 - r};
                case ORIENTATION_RIGHTBOT:
                    return {w - 1 - c, h - 1 - r};
                default:  // ORIENTATION_LEFTBOT
                    return {w - 1 - c, r};
                }
            }();
            out[i * out_width + j] = stored[r * w + c];
        }
    }

    return decompress_result_t{
        .pixels = std::move(upright),
        .width = static_cast<uint32_t>(out_width),
        .height = static_cast<uint32_t>(transposed ? w : h),
        .channels = 4u,
        .bit_depth = 8u,
    };
}


expected<decompress_result_t, string_view> webp_decompress(binary bytes, uint64_t max_pixels)
{
    // Read dimensions and alpha before allocating the output buffer.
    WebPBitstreamFeatures features;
    if (WebPGetFeatures(bytes.data, bytes.size, &features) != VP8_STATUS_OK)
        return std::unexpected("invalid WebP data");
    if (features.has_animation)
        return std::unexpected("animated WebP is not supported");
    if (exceeds_max_pixels(features.width, features.height, max_pixels))
        return std::unexpected(MAX_PIXELS_ERROR);

    // Decode directly into the BEAM-owned RGB or RGBA binary.
    const uint32_t channels = features.has_alpha ? 4 : 3;
    const size_t stride = static_cast<size_t>(features.width) * channels;
    binary pixels(stride * features.height);
    auto decoded = features.has_alpha ? WebPDecodeRGBAInto(bytes.data, bytes.size, pixels.data, pixels.size, stride)
                                      : WebPDecodeRGBInto(bytes.data, bytes.size, pixels.data, pixels.size, stride);
    if (!decoded)
        return std::unexpected("failed to decode WebP");

    return decompress_result_t{
        .pixels = std::move(pixels),
        .width = static_cast<uint32_t>(features.width),
        .height = static_cast<uint32_t>(features.height),
        .channels = channels,
        .bit_depth = 8u,
    };
}

struct webp_picture_guard
{
    WebPPicture* picture;
    ~webp_picture_guard()
    {
        WebPPictureFree(picture);
    }
};

struct webp_writer_guard
{
    WebPMemoryWriter* writer;
    ~webp_writer_guard()
    {
        WebPMemoryWriterClear(writer);
    }
};

expected<binary, string_view> webp_compress(
    binary pixels, int width, int height, int channels, double quality, bool lossless, int effort)
{
    // Validate the raw pixel buffer before passing it to libwebp.
    if (width <= 0 || height <= 0 || width > WEBP_MAX_DIMENSION || height > WEBP_MAX_DIMENSION)
        return std::unexpected("invalid WebP dimensions");
    if ((channels != 3 && channels != 4) || pixels.size != static_cast<size_t>(width) * height * channels)
        return std::unexpected("invalid WebP pixel buffer");

    // Configure compression; exact preserves hidden RGB in transparent pixels.
    WebPConfig config;
    if (!WebPConfigInit(&config))
        return std::unexpected("failed to initialize WebP encoder");
    config.quality = quality;
    config.lossless = lossless;
    config.method = effort;
    config.exact = 1;
    if (!WebPValidateConfig(&config))
        return std::unexpected("invalid WebP encoder options");

    // Import packed RGB/RGBA. ARGB storage is needed for lossless encoding.
    WebPPicture picture;
    if (!WebPPictureInit(&picture))
        return std::unexpected("failed to initialize WebP picture");
    webp_picture_guard picture_guard{&picture};
    picture.width = width;
    picture.height = height;
    picture.use_argb = 1;
    const bool imported = channels == 4 ? WebPPictureImportRGBA(&picture, pixels.data, width * channels)
                                        : WebPPictureImportRGB(&picture, pixels.data, width * channels);
    if (!imported)
        return std::unexpected("failed to import WebP pixels");

    // Encode to a native buffer, with both allocations released by the guards.
    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    webp_writer_guard writer_guard{&writer};
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    if (!WebPEncode(&config, &picture))
        return std::unexpected("failed to encode WebP");

    // Copy the encoded bytes into BEAM-owned memory before releasing the writer.
    binary output(writer.size);
    memcpy(output.data, writer.mem, writer.size);
    return output;
}


int load(ErlNifEnv* caller_env, void** priv_data, ERL_NIF_TERM load_info)
{
    pdf_resource_t::init(caller_env, "poppler");
    tiff_resource_t::init(caller_env, "tiff");
    yielding_resource_t::init(caller_env, "yielding_generator");
    TIFFSetWarningHandler(nullptr);

    return 0;
}


MODULE(
    Elixir.Imagex.C,
    load,
    nullptr,
    nullptr,
    def(jpeg_decompress, DirtyFlags::DirtyCpu),
    def(jpeg_compress, DirtyFlags::DirtyCpu),
    def(png_decompress, DirtyFlags::DirtyCpu),
    def(png_compress, DirtyFlags::DirtyCpu),
    def(jxl_decompress, DirtyFlags::DirtyCpu),
    def(jxl_compress, DirtyFlags::DirtyCpu),
    def(jxl_transcode_from_jpeg, DirtyFlags::DirtyCpu),
    def(jxl_transcode_to_jpeg, DirtyFlags::DirtyCpu),
    def(pdf_load_document, DirtyFlags::DirtyCpu),
    def(pdf_render_page, DirtyFlags::DirtyCpu),
    def(tiff_load_document, DirtyFlags::DirtyCpu),
    def(tiff_render_page, DirtyFlags::DirtyCpu),
    def(webp_decompress, DirtyFlags::DirtyCpu),
    def(webp_compress, DirtyFlags::DirtyCpu), )
