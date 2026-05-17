#include "expp.hpp"
#include <array>
#include <bit>
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

using namespace std;
using namespace expp;

using text_chunk_t = std::tuple<std::vector<uint8_t>, std::vector<uint8_t>, std::vector<uint8_t>, std::vector<uint8_t>>;
using text_chunks_t = std::vector<text_chunk_t>;
constexpr string_view JPEG_XMP_APP1_IDENTIFIER = "http://ns.adobe.com/xap/1.0/\0"sv;

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


// RAII guard for jpeg_decompress_struct.
struct jpeg_decompress_guard
{
    jpeg_decompress_struct* cinfo;
    explicit jpeg_decompress_guard(jpeg_decompress_struct* c) :
        cinfo(c)
    {}
    ~jpeg_decompress_guard()
    {
        if (cinfo)
            jpeg_destroy_decompress(cinfo);
    }
    jpeg_decompress_guard(const jpeg_decompress_guard&) = delete;
    jpeg_decompress_guard& operator=(const jpeg_decompress_guard&) = delete;
    void release()
    {
        cinfo = nullptr;
    }
};


// RAII guard for jpeg_compress_struct.
struct jpeg_compress_guard
{
    jpeg_compress_struct* cinfo;
    explicit jpeg_compress_guard(jpeg_compress_struct* c) :
        cinfo(c)
    {}
    ~jpeg_compress_guard()
    {
        if (cinfo)
            jpeg_destroy_compress(cinfo);
    }
    jpeg_compress_guard(const jpeg_compress_guard&) = delete;
    jpeg_compress_guard& operator=(const jpeg_compress_guard&) = delete;
    void release()
    {
        cinfo = nullptr;
    }
};


void jpeg_error_exit(j_common_ptr cinfo)
{
    char error_message[JMSG_LENGTH_MAX];
    (*(cinfo->err->format_message))(cinfo, error_message);
    throw erl_error<string>(error_message);
}


yielding<expected<decompress_result_t, string>> jpeg_decompress(std::vector<uint8_t> jpeg_bytes)
{
    struct jpeg_error_mgr err;
    struct jpeg_decompress_struct cinfo;
    jpeg_decompress_guard guard(&cinfo);
    yielding_timer timer;

    // create decompressor
    cinfo.err = jpeg_std_error(&err);
    jpeg_create_decompress(&cinfo);
    cinfo.do_fancy_upsampling = FALSE;
    err.error_exit = jpeg_error_exit;

    // set source buffer
    jpeg_mem_src(&cinfo, jpeg_bytes.data(), jpeg_bytes.size());

    // read jpeg header
    jpeg_read_header(&cinfo, TRUE);

    // decompress
    jpeg_start_decompress(&cinfo);

    // Save dimensions before destroying the struct
    const uint32_t out_width = cinfo.output_width;
    const uint32_t out_height = cinfo.output_height;
    const uint32_t num_components = static_cast<uint32_t>(cinfo.num_components);

    unsigned output_bytes = out_width * out_height * num_components;
    binary output(output_bytes);

    // read scanlines
    const auto row_stride = out_width * num_components;
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

    // clean up
    jpeg_finish_decompress(&cinfo);
    guard.release();
    jpeg_destroy_decompress(&cinfo);

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
    optional<vector<uint8_t>> exif_binary,
    optional<vector<uint8_t>> xmp_binary)
{
    struct jpeg_error_mgr err;
    struct jpeg_compress_struct cinfo;
    jpeg_compress_guard guard(&cinfo);
    yielding_timer timer;

    // create the compressor
    cinfo.err = jpeg_std_error(&err);
    jpeg_create_compress(&cinfo);
    err.error_exit = jpeg_error_exit;

    uint8_t* buf = nullptr;
    unsigned long outsize = 0;
    jpeg_mem_dest(&cinfo, &buf, &outsize);

    cinfo.image_width = width;
    cinfo.image_height = height;
    cinfo.input_components = channels;
    cinfo.in_color_space = JCS_RGB;

    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, quality, TRUE);

    // do the actual compression
    jpeg_start_compress(&cinfo, TRUE);

    if (exif_binary.has_value())
    {
        const auto& exif = exif_binary.value();
        vector<uint8_t> app1_payload;
        app1_payload.reserve(6 + exif.size());
        app1_payload.insert(app1_payload.end(), {'E', 'x', 'i', 'f', 0, 0});
        app1_payload.insert(app1_payload.end(), exif.data(), exif.data() + exif.size());

        if (app1_payload.size() > 65533)
        {
            co_yield std::unexpected("EXIF metadata is too large for a JPEG APP1 segment");
            co_return;
        }

        jpeg_write_marker(&cinfo, JPEG_APP0 + 1, app1_payload.data(), static_cast<unsigned int>(app1_payload.size()));
    }

    if (xmp_binary.has_value())
    {
        const auto& xmp = xmp_binary.value();
        vector<uint8_t> app1_payload;
        app1_payload.reserve(JPEG_XMP_APP1_IDENTIFIER.size() + xmp.size());
        app1_payload.insert(app1_payload.end(), JPEG_XMP_APP1_IDENTIFIER.begin(), JPEG_XMP_APP1_IDENTIFIER.end());
        app1_payload.insert(app1_payload.end(), xmp.data(), xmp.data() + xmp.size());

        if (app1_payload.size() > 65533)
        {
            co_yield std::unexpected("XMP metadata is too large for a JPEG APP1 segment");
            co_return;
        }

        jpeg_write_marker(&cinfo, JPEG_APP0 + 1, app1_payload.data(), static_cast<unsigned int>(app1_payload.size()));
    }

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
    guard.release();
    jpeg_destroy_compress(&cinfo);

    // copy the buf to a binary object
    binary out = binary::from_bytes(buf, outsize);
    free(buf);  // free the buf created by jpeg_mem_dest

    co_yield std::move(out);
}


struct png_read_binary
{
    const vector<uint8_t>& data;
    size_t offset = 8;

    png_read_binary(const vector<uint8_t>& data) :
        data(data)
    {}

    void read(png_bytep dest, png_size_t size_to_read)
    {
        std::copy_n(this->data.data() + offset, size_to_read, dest);
        this->offset += size_to_read;
    }
};


void png_error_exit(png_structp png_ptr, const char* error_message)
{
    throw erl_error<string>(error_message);
}


yielding<expected<decompress_result_t, string_view>> png_decompress(vector<uint8_t> png_bytes)
{
    yielding_timer timer;

    // check png signature
    if (png_sig_cmp(png_bytes.data(), 0, 8))
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

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        png_destroy_read_struct(&png_ptr, nullptr, nullptr);
        co_yield std::unexpected("couldn't initialize png info struct");
        co_return;
    }

    try
    {
        // read metadata
        png_read_binary data_wrapper(png_bytes);
        png_set_read_fn(
            png_ptr,
            reinterpret_cast<png_voidp>(&data_wrapper),
            [](png_structp png_ptr, png_bytep dest, png_size_t size_to_read) {
                auto data_wrapper = reinterpret_cast<png_read_binary*>(png_get_io_ptr(png_ptr));
                data_wrapper->read(dest, size_to_read);
            });
        png_set_sig_bytes(png_ptr, 8);
        png_read_info(png_ptr, info_ptr);

        const png_uint_32 width = png_get_image_width(png_ptr, info_ptr);
        const png_uint_32 height = png_get_image_height(png_ptr, info_ptr);
        png_uint_32 bit_depth = png_get_bit_depth(png_ptr, info_ptr);
        png_uint_32 channels = png_get_channels(png_ptr, info_ptr);
        const png_uint_32 color_type = png_get_color_type(png_ptr, info_ptr);
        const auto interlace_type = png_get_interlace_type(png_ptr, info_ptr);

        switch (color_type)
        {
        case PNG_COLOR_TYPE_PALETTE:  // convert palette to RGB
            png_set_palette_to_rgb(png_ptr);
            channels = 3;
            break;
        case PNG_COLOR_TYPE_GRAY:  // expand 1, 2, or 4 bit grayscale to 8 bit grayscale
            if (bit_depth < 8)
                png_set_expand_gray_1_2_4_to_8(png_ptr);
            break;
        }

        if constexpr (std::endian::native == std::endian::little)
        {
            if (bit_depth == 16)
                png_set_swap(png_ptr);
        }

        const unsigned int stride = width * bit_depth * channels / 8;
        binary output(height * stride);

        // Depending on whether the image is interlaced, we need to decode multiple passes
        // See https://github.com/glennrp/libpng/blob/libpng16/libpng-manual.txt and
        // libpng png_read_image's implementation
        int num_passes = 1;

        // if interlaced, we need to get the number of passes
        if (interlace_type == PNG_INTERLACE_ADAM7)
        {
            num_passes = png_set_interlace_handling(png_ptr);
            png_start_read_image(png_ptr);
        }

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
            if (int num_text = png_get_text(png_ptr, info_ptr, &text_ptr, nullptr); num_text > 0)
            {
                for (int i = 0; i < num_text; i++)
                {
                    vector<uint8_t> key(text_ptr[i].key, text_ptr[i].key + strlen(text_ptr[i].key));
                    png_size_t text_length = text_ptr[i].text_length;
                    if (text_ptr[i].compression == PNG_ITXT_COMPRESSION_NONE ||
                        text_ptr[i].compression == PNG_ITXT_COMPRESSION_zTXt)
                    {
                        text_length = text_ptr[i].itxt_length;
                    }

                    vector<uint8_t> text(text_ptr[i].text, text_ptr[i].text + text_length);
                    string_view lang = text_ptr[i].lang != nullptr ? text_ptr[i].lang : "";
                    string_view translated_keyword = text_ptr[i].lang_key != nullptr ? text_ptr[i].lang_key : "";
                    vector<uint8_t> language_tag(lang.begin(), lang.end());
                    vector<uint8_t> translated(translated_keyword.begin(), translated_keyword.end());

                    text_data.push_back(
                        {std::move(key), std::move(text), std::move(language_tag), std::move(translated)});
                }
            }
        }

        png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        png_ptr = nullptr;

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
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_read_struct(&png_ptr, &info_ptr, nullptr);
        throw e;
    }
}


yielding<expected<vector<png_byte>, string_view>> png_compress(
    vector<uint8_t> pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    optional<text_chunks_t> text_chunks)
{
    yielding_timer timer;

    if (channels == 0 || channels > 4)
    {
        co_yield std::unexpected("unsupported number of channels (must be 1-4)");
        co_return;
    }

    png_structp png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, png_error_exit, nullptr);
    if (!png_ptr)
    {
        co_yield std::unexpected("couldn't initialize png write struct");
        co_return;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
    {
        png_destroy_write_struct(&png_ptr, nullptr);
        co_yield std::unexpected("couldn't initialize png info struct");
        co_return;
    }

    try
    {
        // set up the output data, as well as the callback to write into that data
        vector<png_byte> out_data;
        auto png_chunk_producer = [](png_structp png_ptr, png_bytep data, png_size_t length) {
            auto out_data_p = reinterpret_cast<vector<png_byte>*>(png_get_io_ptr(png_ptr));
            std::copy_n(data, length, std::back_inserter(*out_data_p));
        };
        png_set_write_fn(png_ptr, &out_data, png_chunk_producer, nullptr);

        // write header
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
            __builtin_unreachable();  // validated above
        }

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

        if (text_chunks.has_value())
        {
            vector<string> text_keys;
            vector<string> text_values;
            vector<string> language_tags;
            vector<string> translated_keywords;
            vector<png_text> png_text_entries;

            text_keys.reserve(text_chunks->size());
            text_values.reserve(text_chunks->size());
            language_tags.reserve(text_chunks->size());
            translated_keywords.reserve(text_chunks->size());
            png_text_entries.reserve(text_chunks->size());

            for (const auto& [key, value, language_tag, translated_keyword] : *text_chunks)
            {
                text_keys.emplace_back(reinterpret_cast<const char*>(key.data()), key.size());
                text_values.emplace_back(reinterpret_cast<const char*>(value.data()), value.size());
                language_tags.emplace_back(reinterpret_cast<const char*>(language_tag.data()), language_tag.size());
                translated_keywords.emplace_back(
                    reinterpret_cast<const char*>(translated_keyword.data()), translated_keyword.size());

                png_text entry = {};
                entry.compression = PNG_ITXT_COMPRESSION_NONE;
                entry.key = text_keys.back().data();
                entry.text = text_values.back().data();
                entry.text_length = text_values.back().size();
                entry.itxt_length = text_values.back().size();
                entry.lang = language_tags.back().data();
                entry.lang_key = translated_keywords.back().data();
                png_text_entries.push_back(entry);
            }

            if (!png_text_entries.empty())
                png_set_text(png_ptr, info_ptr, png_text_entries.data(), png_text_entries.size());
        }

        png_write_info(png_ptr, info_ptr);

        if constexpr (std::endian::native == std::endian::little)
        {
            if (bit_depth == 16)
                png_set_swap(png_ptr);
        }

        // write the pixels
        const unsigned int stride = width * channels * bit_depth / 8;
        for (size_t i = 0; i < height; i++)
        {
            png_write_row(png_ptr, pixels.data() + i * stride);

            if (timer.times_up())
            {
                co_yield nullopt;
                timer.reset();
            }
        }

        // cleanup
        png_write_end(png_ptr, nullptr);
        png_destroy_write_struct(&png_ptr, &info_ptr);
        png_ptr = nullptr;

        co_yield std::move(out_data);
    }
    catch (erl_error<string>& e)
    {
        if (png_ptr)
            png_destroy_write_struct(&png_ptr, &info_ptr);
        throw e;
    }
}


static_assert(JXL_ENC_SUCCESS == 0 && JXL_DEC_SUCCESS == 0);

// NOTE: This macro uses `return`, NOT `co_return`. It is NOT safe to use inside coroutines.
#define JXL_ENSURE_SUCCESS(func, ...)                                                                                  \
    if (func(__VA_ARGS__) != 0)                                                                                        \
    {                                                                                                                  \
        return std::unexpected(#func " failed");                                                                       \
    }


enum class jxl_box_kind
{
    none,
    exif,
    xml,
    jumb,
};


static optional<binary> finalize_jxl_box_data(std::vector<uint8_t>& box_data, JxlDecoder* dec)
{
    size_t remaining = JxlDecoderReleaseBoxBuffer(dec);
    if (remaining > box_data.size())
        return nullopt;

    box_data.resize(box_data.size() - remaining);
    return binary::from_bytes(box_data.data(), box_data.size());
}


// Parse JXL EXIF box data, handling the 4-byte big-endian offset prefix.
static optional<binary> parse_jxl_exif(const binary& exif_data)
{
    if (exif_data.size < 4)
        return nullopt;

    // The first 4 bytes are a big-endian offset (usually 0)
    size_t offset = static_cast<size_t>(exif_data.data[0]) << 24 | static_cast<size_t>(exif_data.data[1]) << 16 |
                    static_cast<size_t>(exif_data.data[2]) << 8 | static_cast<size_t>(exif_data.data[3]);

    if (4 + offset >= exif_data.size)
        return nullopt;

    return binary::from_bytes(exif_data.data + 4 + offset, exif_data.size - 4 - offset);
}


static optional<jxl_box_kind> jxl_box_kind_from_type(const JxlBoxType box_type)
{
    const string_view type(box_type, 4);
    if (type == "Exif")
        return jxl_box_kind::exif;
    if (type == "xml ")
        return jxl_box_kind::xml;
    if (type == "jumb")
        return jxl_box_kind::jumb;

    return nullopt;
}


static expected<void, string_view> append_jxl_box(decompress_result_t& result, jxl_box_kind box_kind, binary box_data)
{
    switch (box_kind)
    {
    case jxl_box_kind::none:
        return {};

    case jxl_box_kind::exif: {
        optional<binary> exif = parse_jxl_exif(box_data);
        if (!exif.has_value())
            return std::unexpected("invalid JXL metadata box");
        result.exif = std::move(exif.value());
        return {};
    }

    case jxl_box_kind::xml:
        result.xml_boxes.push_back(std::move(box_data));
        return {};

    case jxl_box_kind::jumb:
        result.jumb_boxes.push_back(std::move(box_data));
        return {};
    }

    return {};
}


static optional<array<char, 4>> jxl_box_type_from_atom(const atom& box_type_atom)
{
    if (box_type_atom == "xml"sv)
        return array<char, 4>{'x', 'm', 'l', ' '};
    if (box_type_atom == "jumb"sv)
        return array<char, 4>{'j', 'u', 'm', 'b'};

    return nullopt;
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
    {
        fprintf(stderr, "JxlEncoderProcessOutput failed with status: %d\n", process_result);
        return std::unexpected("JxlEncoderProcessOutput failed");
    }

    return compressed;
}


JxlBasicInfo jxl_basic_info_from_pixel_format(const JxlPixelFormat& pixel_format)
{
    JxlBasicInfo basic_info;
    JxlEncoderInitBasicInfo(&basic_info);

    switch (pixel_format.data_type)
    {
    case JXL_TYPE_FLOAT:
        basic_info.bits_per_sample = 32;
        basic_info.exponent_bits_per_sample = 8;
        break;
    case JXL_TYPE_FLOAT16:
        basic_info.bits_per_sample = 16;
        basic_info.exponent_bits_per_sample = 5;
        break;
    case JXL_TYPE_UINT8:
        basic_info.bits_per_sample = 8;
        basic_info.exponent_bits_per_sample = 0;
        break;
    case JXL_TYPE_UINT16:
        basic_info.bits_per_sample = 16;
        basic_info.exponent_bits_per_sample = 0;
        break;
    }

    if (pixel_format.num_channels < 3)
        basic_info.num_color_channels = 1;
    else
        basic_info.num_color_channels = 3;

    if (pixel_format.num_channels == 2 || pixel_format.num_channels == 4)
    {
        basic_info.alpha_exponent_bits = basic_info.exponent_bits_per_sample;
        basic_info.alpha_bits = basic_info.bits_per_sample;
        basic_info.num_extra_channels = 1;
    }
    else
    {
        basic_info.alpha_exponent_bits = 0;
        basic_info.alpha_bits = 0;
    }

    return basic_info;
}


expected<decompress_result_t, string_view> jxl_decompress(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(
        JxlDecoderSubscribeEvents,
        dec.get(),
        JXL_DEC_BASIC_INFO | JXL_DEC_COLOR_ENCODING | JXL_DEC_FULL_IMAGE | JXL_DEC_BOX);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());
    JXL_ENSURE_SUCCESS(JxlDecoderSetDecompressBoxes, dec.get(), JXL_TRUE);

    JXL_ENSURE_SUCCESS(JxlDecoderSetInput, dec.get(), jxl_bytes.data, jxl_bytes.size);

    decompress_result_t result{};
    uint32_t exponent_bits_per_sample = 0;
    const constexpr size_t chunk_size = 0xffff;
    jxl_box_kind current_box_kind = jxl_box_kind::none;
    std::vector<uint8_t> current_box_data;

    int need_more_input_retries = 0;
    const int max_need_more_input_retries = 3;

    auto finish_current_box = [&]() -> expected<void, string_view> {
        if (current_box_kind == jxl_box_kind::none)
            return {};

        optional<binary> box_data = finalize_jxl_box_data(current_box_data, dec.get());
        if (!box_data.has_value())
            return std::unexpected("invalid JXL metadata box");

        if (auto append_result = append_jxl_box(result, current_box_kind, std::move(box_data.value()));
            !append_result.has_value())
            return std::unexpected(append_result.error());

        current_box_kind = jxl_box_kind::none;
        current_box_data.clear();
        return {};
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
            if (++need_more_input_retries > max_need_more_input_retries)
                return std::unexpected("Decoder requested more input but all input was already provided");
            JxlDecoderReleaseInput(dec.get());
            JxlDecoderSetInput(dec.get(), jxl_bytes.data, jxl_bytes.size);
        }
        else if (status == JXL_DEC_BASIC_INFO)
        {
            JxlBasicInfo info;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBasicInfo, dec.get(), &info);

            if (info.exponent_bits_per_sample != 0)
                return std::unexpected("FLOAT32 images are currently not yet supported");

            result.width = info.xsize;
            result.height = info.ysize;
            result.channels = info.num_color_channels + info.num_extra_channels;
            result.bit_depth = info.bits_per_sample;
            exponent_bits_per_sample = info.exponent_bits_per_sample;
        }
        else if (status == JXL_DEC_COLOR_ENCODING)
        {
            // Color encoding event received; no action needed.
        }
        else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER)
        {
            JxlDataType data_type;
            if (result.bit_depth == 8)
                data_type = JXL_TYPE_UINT8;
            else if (result.bit_depth == 16)
            {
                if (exponent_bits_per_sample > 0)
                    data_type = JXL_TYPE_FLOAT;  // should be float16, but we're not going to worry about that for now
                else
                    data_type = JXL_TYPE_UINT16;
            }
            else if (result.bit_depth == 32)
                data_type = JXL_TYPE_FLOAT;
            else
                return std::unexpected("unrecognized bit depth");
            JxlPixelFormat format = {result.channels, data_type, JXL_NATIVE_ENDIAN, 0};

            size_t buffer_size;
            JXL_ENSURE_SUCCESS(JxlDecoderImageOutBufferSize, dec.get(), &format, &buffer_size);
            if (buffer_size != result.width * result.height * result.channels * result.bit_depth / 8)
                return std::unexpected("Invalid out buffer size");
            result.pixels = binary{buffer_size};
            JXL_ENSURE_SUCCESS(JxlDecoderSetImageOutBuffer, dec.get(), &format, result.pixels.data, result.pixels.size);
        }
        else if (status == JXL_DEC_BOX)
        {
            if (auto box_result = finish_current_box(); !box_result.has_value())
                return std::unexpected(box_result.error());

            JxlBoxType box_type;
            JXL_ENSURE_SUCCESS(JxlDecoderGetBoxType, dec.get(), box_type, JXL_TRUE);
            optional<jxl_box_kind> next_box_kind = jxl_box_kind_from_type(box_type);
            if (!next_box_kind.has_value())
                continue;

            current_box_kind = next_box_kind.value();
            current_box_data.resize(chunk_size);
            JxlDecoderSetBoxBuffer(dec.get(), current_box_data.data(), current_box_data.size());
        }
        else if (status == JXL_DEC_BOX_NEED_MORE_OUTPUT)
        {
            const size_t remaining = JxlDecoderReleaseBoxBuffer(dec.get());
            const size_t output_pos = current_box_data.size() - remaining;
            current_box_data.resize(current_box_data.size() + chunk_size);
            JXL_ENSURE_SUCCESS(
                JxlDecoderSetBoxBuffer,
                dec.get(),
                current_box_data.data() + output_pos,
                current_box_data.size() - output_pos);
        }
        else if (status == JXL_DEC_FULL_IMAGE)
        {
            // Nothing to do. Do not yet return. If the image is an animation, more
            // full frames may be decoded. This example only keeps the last one.
        }
        else if (status == JXL_DEC_SUCCESS)
        {
            if (auto box_result = finish_current_box(); !box_result.has_value())
                return std::unexpected(box_result.error());
            return result;
        }
        else
        {
            return std::unexpected("Unknown decoder status");
        }
    }
}


expected<vector<uint8_t>, string_view> jxl_compress(
    const binary& pixels,
    uint32_t width,
    uint32_t height,
    uint32_t channels,
    uint32_t bit_depth,
    optional<binary> exif_binary,
    optional<vector<pair<atom, binary>>> jxl_boxes,
    double distance,
    bool lossless,
    int effort,
    int progressive,
    int order)
{
    static auto runner = JxlThreadParallelRunnerMake(
        /*memory_manager=*/nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());

    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderSetParallelRunner, enc.get(), JxlThreadParallelRunner, runner.get());

    if (exif_binary.has_value() || jxl_boxes.has_value())
        JXL_ENSURE_SUCCESS(JxlEncoderUseBoxes, enc.get());

    JxlPixelFormat pixel_format = {channels, bit_depth == 16 ? JXL_TYPE_UINT16 : JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};

    JxlBasicInfo basic_info = jxl_basic_info_from_pixel_format(pixel_format);
    basic_info.xsize = width;
    basic_info.ysize = height;
    basic_info.uses_original_profile = lossless;
    JXL_ENSURE_SUCCESS(JxlEncoderSetBasicInfo, enc.get(), &basic_info);

    JxlColorEncoding color_encoding = {};
    const bool is_grayscale = pixel_format.num_channels < 3;
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

    if (exif_binary.has_value())
    {
        const JxlBoxType exif_box_type = {'E', 'x', 'i', 'f'};
        vector<uint8_t> exif_box(4 + exif_binary->size);
        exif_box[0] = exif_box[1] = exif_box[2] = exif_box[3] = 0;
        std::copy_n(exif_binary->data, exif_binary->size, exif_box.data() + 4);
        JXL_ENSURE_SUCCESS(JxlEncoderAddBox, enc.get(), exif_box_type, exif_box.data(), exif_box.size(), JXL_FALSE);
    }

    if (jxl_boxes.has_value())
    {
        for (const auto& [box_type_atom, box_contents] : jxl_boxes.value())
        {
            optional<array<char, 4>> box_type = jxl_box_type_from_atom(box_type_atom);
            if (!box_type.has_value())
                return std::unexpected("unsupported JXL metadata box type");

            JXL_ENSURE_SUCCESS(
                JxlEncoderAddBox, enc.get(), box_type->data(), box_contents.data, box_contents.size, JXL_FALSE);
        }
    }

    JXL_ENSURE_SUCCESS(JxlEncoderAddImageFrame, encoder_options, &pixel_format, pixels.data, pixels.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view> jxl_transcode_from_jpeg(
    const binary& jpeg_bytes, int effort, int store_jpeg_metadata)
{
    auto enc = JxlEncoderMake(/*memory_manager=*/nullptr);

    JXL_ENSURE_SUCCESS(JxlEncoderUseContainer, enc.get(), JXL_TRUE);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), JXL_TRUE);

    auto encoder_options = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JXL_ENSURE_SUCCESS(JxlEncoderStoreJPEGMetadata, enc.get(), store_jpeg_metadata);
    JXL_ENSURE_SUCCESS(JxlEncoderFrameSettingsSetOption, encoder_options, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JXL_ENSURE_SUCCESS(JxlEncoderAddJPEGFrame, encoder_options, jpeg_bytes.data, jpeg_bytes.size);
    JxlEncoderCloseInput(enc.get());

    return jxl_collect_compressed(enc.get());
}


expected<vector<uint8_t>, string_view> jxl_transcode_to_jpeg(const binary& jxl_bytes)
{
    // Multi-threaded parallel runner.
    static auto runner = JxlResizableParallelRunnerMake(nullptr);

    auto dec = JxlDecoderMake(nullptr);
    JXL_ENSURE_SUCCESS(JxlDecoderSubscribeEvents, dec.get(), JXL_DEC_FULL_IMAGE | JXL_DEC_JPEG_RECONSTRUCTION);
    JXL_ENSURE_SUCCESS(JxlDecoderSetParallelRunner, dec.get(), JxlResizableParallelRunner, runner.get());

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
            return std::unexpected("Unknown decoder status");
        }
    }
}


struct TIFFWrapper
{
    TIFF* tiff;
    unique_ptr<stringstream> sstream;

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


expected<decompress_result_t, string_view> pdf_render_page(pdf_resource_t document_resource, int page_idx, int dpi)
{
    auto& document = document_resource.get();
    if (page_idx < 0 || page_idx >= document->pages())
        throw std::invalid_argument("page index out of range");

    unique_ptr<poppler::page> page(document->create_page(page_idx));
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


expected<decompress_result_t, string_view> tiff_render_page(tiff_resource_t document_resource, int page_index)
{
    auto& [document, _] = document_resource.get();

    if (!TIFFSetDirectory(document, page_index))
        return std::unexpected("failed to set TIFF directory");

    int width = 0, height = 0;
    if (!TIFFGetField(document, TIFFTAG_IMAGEWIDTH, &width))
        return std::unexpected("failed to read TIFF image width");
    if (!TIFFGetField(document, TIFFTAG_IMAGELENGTH, &height))
        return std::unexpected("failed to read TIFF image height");
    if (width <= 0 || height <= 0)
        return std::unexpected("invalid TIFF image dimensions");

    binary pixels{static_cast<size_t>(width * height * 4)};
    TIFFReadRGBAImageOriented(document, width, height, reinterpret_cast<uint32_t*>(pixels.data), 1, 0);

    return decompress_result_t{
        .pixels = std::move(pixels),
        .width = static_cast<uint32_t>(width),
        .height = static_cast<uint32_t>(height),
        .channels = 4u,
        .bit_depth = 8u,
    };
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
    def(tiff_render_page, DirtyFlags::DirtyCpu), )
