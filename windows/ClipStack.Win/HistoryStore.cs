using System.Text.Json;

namespace ClipStack.Win;

/// <summary>
/// Persistent clipboard history, newest first. Port of the macOS
/// ClipStackCore.HistoryStore: dedupe by content hash (promote to front),
/// pinned items survive trimming, JSON + PNG side files under %APPDATA%.
/// UI-thread only, same as the macOS version.
/// </summary>
public class HistoryStore
{
    public List<ClipItem> Items { get; } = new();
    public int MaxItems { get; }
    public string Directory { get; }
    public string ImagesDirectory => Path.Combine(Directory, "images");
    private string HistoryFile => Path.Combine(Directory, "history.json");

    public event Action? OnChange;

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = false };

    public HistoryStore(string directory, int maxItems = 300)
    {
        Directory = directory;
        MaxItems = Math.Max(1, maxItems);
        System.IO.Directory.CreateDirectory(directory);
        System.IO.Directory.CreateDirectory(ImagesDirectory);
        Load();
    }

    public bool PromoteIfExists(string hash)
    {
        var idx = Items.FindIndex(i => i.ContentHash == hash);
        if (idx < 0) return false;
        var item = Items[idx];
        Items.RemoveAt(idx);
        item.CreatedAt = DateTime.Now;
        Items.Insert(0, item);
        PersistAndNotify();
        return true;
    }

    public void Add(ClipItem item)
    {
        var idx = Items.FindIndex(i => i.ContentHash == item.ContentHash);
        if (idx >= 0)
        {
            // Same content re-copied: keep existing entry (and pin state).
            if (item.ImageFileName != null && item.ImageFileName != Items[idx].ImageFileName)
                TryDelete(Path.Combine(ImagesDirectory, item.ImageFileName));
            var existing = Items[idx];
            Items.RemoveAt(idx);
            existing.CreatedAt = item.CreatedAt;
            if (item.SourceApp != null) existing.SourceApp = item.SourceApp;
            Items.Insert(0, existing);
        }
        else
        {
            Items.Insert(0, item);
            TrimIfNeeded();
        }
        PersistAndNotify();
    }

    public void Delete(Guid id)
    {
        var idx = Items.FindIndex(i => i.Id == id);
        if (idx < 0) return;
        RemoveSideFiles(Items[idx]);
        Items.RemoveAt(idx);
        PersistAndNotify();
    }

    public void TogglePin(Guid id)
    {
        var item = Items.FirstOrDefault(i => i.Id == id);
        if (item == null) return;
        item.Pinned = !item.Pinned;
        PersistAndNotify();
    }

    public void Clear(bool keepPinned = true)
    {
        foreach (var victim in Items.Where(i => !keepPinned || !i.Pinned))
            RemoveSideFiles(victim);
        Items.RemoveAll(i => !keepPinned || !i.Pinned);
        PersistAndNotify();
    }

    public string StoreImagePng(byte[] data)
    {
        var name = Guid.NewGuid().ToString("N") + ".png";
        File.WriteAllBytes(Path.Combine(ImagesDirectory, name), data);
        return name;
    }

    public byte[]? ImageData(ClipItem item)
    {
        if (item.ImageFileName == null) return null;
        var path = Path.Combine(ImagesDirectory, item.ImageFileName);
        return File.Exists(path) ? File.ReadAllBytes(path) : null;
    }

    private void TrimIfNeeded()
    {
        while (Items.Count > MaxItems)
        {
            var idx = Items.FindLastIndex(i => !i.Pinned);
            if (idx < 0) idx = Items.Count - 1; // everything pinned: drop oldest
            RemoveSideFiles(Items[idx]);
            Items.RemoveAt(idx);
        }
    }

    private void RemoveSideFiles(ClipItem item)
    {
        if (item.ImageFileName != null)
            TryDelete(Path.Combine(ImagesDirectory, item.ImageFileName));
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* best effort */ }
    }

    private void PersistAndNotify()
    {
        Save();
        OnChange?.Invoke();
    }

    public void Save()
    {
        try
        {
            File.WriteAllText(HistoryFile, JsonSerializer.Serialize(Items, JsonOpts));
        }
        catch { /* best effort */ }
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(HistoryFile)) return;
            var loaded = JsonSerializer.Deserialize<List<ClipItem>>(File.ReadAllText(HistoryFile));
            if (loaded != null) Items.AddRange(loaded);
        }
        catch { /* corrupt history: start fresh */ }
    }
}
