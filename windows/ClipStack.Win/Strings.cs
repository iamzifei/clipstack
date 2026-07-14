using System.Globalization;

namespace ClipStack.Win;

/// <summary>
/// Minimal localization matching the macOS app's 7 languages.
/// Resolved once from the OS UI culture.
/// </summary>
public static class Strings
{
    private static readonly string Lang = Resolve();

    private static string Resolve()
    {
        var culture = CultureInfo.CurrentUICulture;
        var name = culture.Name;
        if (name.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
        {
            var traditional = name.Contains("TW") || name.Contains("HK") || name.Contains("MO") || name.Contains("Hant");
            return traditional ? "zh-Hant" : "zh-Hans";
        }
        return culture.TwoLetterISOLanguageName switch
        {
            "ja" => "ja",
            "ko" => "ko",
            "es" => "es",
            "fr" => "fr",
            _ => "en",
        };
    }

    public static string T(string key) =>
        Table.TryGetValue(key, out var row) && row.TryGetValue(Lang, out var s)
            ? s
            : (Table.TryGetValue(key, out var r2) && r2.TryGetValue("en", out var en) ? en : key);

    private static readonly Dictionary<string, Dictionary<string, string>> Table = new()
    {
        ["search_placeholder"] = new()
        {
            ["en"] = "Search clipboard history…",
            ["zh-Hans"] = "搜索剪贴板历史…",
            ["zh-Hant"] = "搜尋剪貼簿歷史…",
            ["ja"] = "クリップボード履歴を検索…",
            ["ko"] = "클립보드 기록 검색…",
            ["es"] = "Buscar en el historial…",
            ["fr"] = "Rechercher dans l'historique…",
        },
        ["items_count"] = new()
        {
            ["en"] = "{0} items",
            ["zh-Hans"] = "{0} 条",
            ["zh-Hant"] = "{0} 條",
            ["ja"] = "{0} 件",
            ["ko"] = "{0}개",
            ["es"] = "{0} elementos",
            ["fr"] = "{0} éléments",
        },
        ["empty_history"] = new()
        {
            ["en"] = "Clipboard history is empty",
            ["zh-Hans"] = "剪贴板历史为空",
            ["zh-Hant"] = "剪貼簿歷史為空",
            ["ja"] = "クリップボード履歴は空です",
            ["ko"] = "클립보드 기록이 비어 있습니다",
            ["es"] = "El historial está vacío",
            ["fr"] = "L'historique est vide",
        },
        ["toast_copied"] = new()
        {
            ["en"] = "Copied",
            ["zh-Hans"] = "已复制",
            ["zh-Hant"] = "已複製",
            ["ja"] = "コピーしました",
            ["ko"] = "복사됨",
            ["es"] = "Copiado",
            ["fr"] = "Copié",
        },
        ["menu_open"] = new()
        {
            ["en"] = "Open History Panel\tCtrl+Shift+V",
            ["zh-Hans"] = "打开历史面板\tCtrl+Shift+V",
            ["zh-Hant"] = "打開歷史面板\tCtrl+Shift+V",
            ["ja"] = "履歴パネルを開く\tCtrl+Shift+V",
            ["ko"] = "기록 패널 열기\tCtrl+Shift+V",
            ["es"] = "Abrir panel de historial\tCtrl+Shift+V",
            ["fr"] = "Ouvrir le panneau\tCtrl+Shift+V",
        },
        ["menu_settings"] = new()
        {
            ["en"] = "Settings…\tCtrl+.",
            ["zh-Hans"] = "设置…\tCtrl+.",
            ["zh-Hant"] = "設定…\tCtrl+.",
            ["ja"] = "設定…\tCtrl+.",
            ["ko"] = "설정…\tCtrl+.",
            ["es"] = "Ajustes…\tCtrl+.",
            ["fr"] = "Réglages…\tCtrl+.",
        },
        ["menu_pause"] = new()
        {
            ["en"] = "Pause Monitoring",
            ["zh-Hans"] = "暂停监控",
            ["zh-Hant"] = "暫停監控",
            ["ja"] = "監視を一時停止",
            ["ko"] = "모니터링 일시 중지",
            ["es"] = "Pausar monitoreo",
            ["fr"] = "Suspendre la surveillance",
        },
        ["menu_resume"] = new()
        {
            ["en"] = "Resume Monitoring",
            ["zh-Hans"] = "恢复监控",
            ["zh-Hant"] = "恢復監控",
            ["ja"] = "監視を再開",
            ["ko"] = "모니터링 재개",
            ["es"] = "Reanudar monitoreo",
            ["fr"] = "Reprendre la surveillance",
        },
        ["menu_clear"] = new()
        {
            ["en"] = "Clear History (Keep Pinned)…",
            ["zh-Hans"] = "清空历史（保留置顶）…",
            ["zh-Hant"] = "清除歷史（保留置頂）…",
            ["ja"] = "履歴を消去（ピン留めは保持）…",
            ["ko"] = "기록 지우기(고정 유지)…",
            ["es"] = "Borrar historial (conservar fijados)…",
            ["fr"] = "Effacer l'historique (garder épinglés)…",
        },
        ["menu_quit"] = new()
        {
            ["en"] = "Quit ClipStack",
            ["zh-Hans"] = "退出 ClipStack",
            ["zh-Hant"] = "結束 ClipStack",
            ["ja"] = "ClipStack を終了",
            ["ko"] = "ClipStack 종료",
            ["es"] = "Salir de ClipStack",
            ["fr"] = "Quitter ClipStack",
        },
        ["clear_title"] = new()
        {
            ["en"] = "Clear clipboard history?",
            ["zh-Hans"] = "清空剪贴板历史？",
            ["zh-Hant"] = "清除剪貼簿歷史？",
            ["ja"] = "クリップボード履歴を消去しますか？",
            ["ko"] = "클립보드 기록을 지우시겠습니까?",
            ["es"] = "¿Borrar el historial?",
            ["fr"] = "Effacer l'historique ?",
        },
        ["clear_msg"] = new()
        {
            ["en"] = "All unpinned entries will be deleted. This cannot be undone.",
            ["zh-Hans"] = "将删除所有未置顶的记录。此操作不可撤销。",
            ["zh-Hant"] = "將刪除所有未置頂的記錄。此操作無法復原。",
            ["ja"] = "ピン留めされていない項目をすべて削除します。取り消せません。",
            ["ko"] = "고정되지 않은 모든 항목이 삭제됩니다. 취소할 수 없습니다.",
            ["es"] = "Se eliminarán todas las entradas no fijadas. No se puede deshacer.",
            ["fr"] = "Toutes les entrées non épinglées seront supprimées. Irréversible.",
        },
        ["settings_title"] = new()
        {
            ["en"] = "ClipStack Settings",
            ["zh-Hans"] = "ClipStack 设置",
            ["zh-Hant"] = "ClipStack 設定",
            ["ja"] = "ClipStack 設定",
            ["ko"] = "ClipStack 설정",
            ["es"] = "Ajustes de ClipStack",
            ["fr"] = "Réglages de ClipStack",
        },
        ["login_toggle"] = new()
        {
            ["en"] = "Launch at startup",
            ["zh-Hans"] = "开机自动启动",
            ["zh-Hant"] = "開機自動啟動",
            ["ja"] = "起動時に実行",
            ["ko"] = "시작 시 실행",
            ["es"] = "Abrir al iniciar Windows",
            ["fr"] = "Lancer au démarrage",
        },
        ["hotkeys_note"] = new()
        {
            ["en"] = "Hotkeys: Ctrl+Shift+V history panel, Ctrl+. settings (fixed in this version)",
            ["zh-Hans"] = "快捷键：Ctrl+Shift+V 历史面板，Ctrl+. 设置（本版本固定）",
            ["zh-Hant"] = "快速鍵：Ctrl+Shift+V 歷史面板，Ctrl+. 設定（本版本固定）",
            ["ja"] = "ショートカット：Ctrl+Shift+V 履歴、Ctrl+. 設定（このバージョンでは固定）",
            ["ko"] = "단축키: Ctrl+Shift+V 기록, Ctrl+. 설정(이 버전에서는 고정)",
            ["es"] = "Atajos: Ctrl+Shift+V historial, Ctrl+. ajustes (fijos en esta versión)",
            ["fr"] = "Raccourcis : Ctrl+Shift+V historique, Ctrl+. réglages (fixes)",
        },
        ["version"] = new()
        {
            ["en"] = "Version",
            ["zh-Hans"] = "版本",
            ["zh-Hant"] = "版本",
            ["ja"] = "バージョン",
            ["ko"] = "버전",
            ["es"] = "Versión",
            ["fr"] = "Version",
        },
        ["hints"] = new()
        {
            ["en"] = "Enter copy · Ctrl+1-9 quick copy · Ctrl+P pin · Ctrl+Del delete · Esc close",
            ["zh-Hans"] = "回车复制 · Ctrl+1-9 快速复制 · Ctrl+P 置顶 · Ctrl+Del 删除 · Esc 关闭",
            ["zh-Hant"] = "Enter 複製 · Ctrl+1-9 快速複製 · Ctrl+P 置頂 · Ctrl+Del 刪除 · Esc 關閉",
            ["ja"] = "Enter コピー · Ctrl+1-9 クイック · Ctrl+P ピン · Ctrl+Del 削除 · Esc 閉じる",
            ["ko"] = "Enter 복사 · Ctrl+1-9 빠른 복사 · Ctrl+P 고정 · Ctrl+Del 삭제 · Esc 닫기",
            ["es"] = "Enter copiar · Ctrl+1-9 rápido · Ctrl+P fijar · Ctrl+Del eliminar · Esc cerrar",
            ["fr"] = "Entrée copier · Ctrl+1-9 rapide · Ctrl+P épingler · Ctrl+Suppr supprimer · Échap fermer",
        },
        ["image_word"] = new()
        {
            ["en"] = "Image",
            ["zh-Hans"] = "图片",
            ["zh-Hant"] = "圖片",
            ["ja"] = "画像",
            ["ko"] = "이미지",
            ["es"] = "Imagen",
            ["fr"] = "Image",
        },
        ["files_prefix"] = new()
        {
            ["en"] = "{0} files: ",
            ["zh-Hans"] = "{0} 个文件：",
            ["zh-Hant"] = "{0} 個檔案：",
            ["ja"] = "{0} 個のファイル：",
            ["ko"] = "파일 {0}개: ",
            ["es"] = "{0} archivos: ",
            ["fr"] = "{0} fichiers : ",
        },
        ["empty_text"] = new()
        {
            ["en"] = "(empty text)",
            ["zh-Hans"] = "（空白文本）",
            ["zh-Hant"] = "（空白文字）",
            ["ja"] = "（空のテキスト）",
            ["ko"] = "(빈 텍스트)",
            ["es"] = "(texto vacío)",
            ["fr"] = "(texte vide)",
        },
    };
}
