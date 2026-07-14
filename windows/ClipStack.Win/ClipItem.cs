using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace ClipStack.Win;

public enum ClipKind { Text, Image, File }

/// <summary>
/// One clipboard history entry. Mirrors the macOS ClipStackCore model:
/// image bytes live as PNG files next to the history JSON, not inline.
/// </summary>
public class ClipItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ClipKind Kind { get; set; }
    public string ContentHash { get; set; } = "";
    public string? PlainText { get; set; }
    public string? ImageFileName { get; set; }
    public int? ImagePixelWidth { get; set; }
    public int? ImagePixelHeight { get; set; }
    public List<string>? FilePaths { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public bool Pinned { get; set; }
    public string? SourceApp { get; set; }
    public long ByteSize { get; set; }

    [JsonIgnore]
    public string PreviewLine
    {
        get
        {
            switch (Kind)
            {
                case ClipKind.Text:
                    var flat = (PlainText ?? "").Replace("\r", "").Replace("\n", " ⏎ ").Trim();
                    if (flat.Length == 0) return Strings.T("empty_text");
                    return flat.Length > 90 ? flat[..90] : flat;
                case ClipKind.Image:
                    var dims = ImagePixelWidth.HasValue ? $"{ImagePixelWidth}×{ImagePixelHeight} " : "";
                    return $"{Strings.T("image_word")} {dims}({ByteSize / 1024} KB)";
                default:
                    var names = (FilePaths ?? new()).Select(Path.GetFileName).ToList();
                    if (names.Count == 1) return names[0] ?? "";
                    return string.Format(Strings.T("files_prefix"), names.Count) + string.Join(", ", names.Take(3));
            }
        }
    }

    [JsonIgnore]
    public string SearchText => Kind switch
    {
        ClipKind.Text => PlainText ?? "",
        ClipKind.File => string.Join("\n", FilePaths ?? new()),
        _ => "image 图片 " + (SourceApp ?? ""),
    };

    public static string HashOf(byte[] data) =>
        Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    public static string HashOfText(string s) => "t-" + HashOf(Encoding.UTF8.GetBytes(s));
    public static string HashOfImage(byte[] png) => "i-" + HashOf(png);
    public static string HashOfFiles(IEnumerable<string> paths) =>
        "f-" + HashOf(Encoding.UTF8.GetBytes(string.Join("\0", paths)));
}
