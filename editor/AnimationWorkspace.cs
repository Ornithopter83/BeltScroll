using System.Drawing.Drawing2D;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Forms;

namespace BeltScrollEditor;

public sealed class AnimationDocument
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
    [JsonPropertyName("clips")] public List<AnimationClip> Clips { get; set; } = [];
}

public sealed class AnimationClip
{
    [JsonPropertyName("id")] public string Id { get; set; } = "attack1";
    [JsonPropertyName("frames")] public List<AnimationFrame> Frames { get; set; } = [];
}

public sealed class AnimationFrame
{
    [JsonPropertyName("texture")] public string? Texture { get; set; } = "";
    [JsonPropertyName("phase")] public string Phase { get; set; } = "startup";
    [JsonPropertyName("duration")] public double Duration { get; set; } = 0.1;
    [JsonPropertyName("foot_anchor")] public FootAnchor FootAnchor { get; set; } = new();
    [JsonPropertyName("approval_state")] public string ApprovalState { get; set; } = "review";
}

[JsonConverter(typeof(FootAnchorJsonConverter))]
public sealed class FootAnchor
{
    [JsonPropertyName("x")] public double X { get; set; } = 0.5;
    [JsonPropertyName("y")] public double Y { get; set; } = 0.9;
}

public sealed class FootAnchorJsonConverter : JsonConverter<FootAnchor>
{
    public override FootAnchor Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.StartObject) throw new JsonException("foot_anchor must be an object with normalized x and y numbers.");
        using var value = JsonDocument.ParseValue(ref reader);
        return new FootAnchor { X = value.RootElement.GetProperty("x").GetDouble(), Y = value.RootElement.GetProperty("y").GetDouble() };
    }
    public override void Write(Utf8JsonWriter writer, FootAnchor value, JsonSerializerOptions options)
    {
        writer.WriteStartObject(); writer.WriteNumber("x", value.X); writer.WriteNumber("y", value.Y); writer.WriteEndObject();
    }
}

/// <summary>Art review workspace whose files are kept in an independent temporary project folder.</summary>
public sealed class AnimationWorkspaceForm : Form
{
    private readonly ListBox frameList = new() { Dock = DockStyle.Fill, IntegralHeight = false };
    private readonly ComboBox clipSelect = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
    private readonly PicturePreview preview = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(54, 58, 66) };
    private readonly PicturePreview leftPreview = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(54, 58, 66), Mirror = true };
    private readonly ArtComparisonPanel comparisonPanel = new() { Dock = DockStyle.Fill };
    private readonly TabControl previewTabs = new() { Dock = DockStyle.Fill };
    private readonly ComboBox phase = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 135 };
    private readonly NumericUpDown duration = new() { DecimalPlaces = 3, Increment = 0.025M, Minimum = 0.01M, Maximum = 10, Width = 100 };
    private readonly ComboBox approval = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 112 };
    private readonly TextBox clipId = new() { Text = "attack1", Width = 110 };
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(6) };
    private readonly System.Windows.Forms.Timer playback = new() { Interval = 10 };
    private readonly CheckBox intermediatePlayback = new() { Text = "50ms 중간동작", AutoSize = true };
    private readonly CheckBox[] reviewChecks = [new() { Text = "얼굴", AutoSize = true }, new() { Text = "귀", AutoSize = true }, new() { Text = "의상", AutoSize = true }, new() { Text = "지지발", AutoSize = true }, new() { Text = "모션 연결", AutoSize = true }];
    private readonly ComboBox reviewOpinion = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 90 };
    private readonly TextBox reviewComment = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill };
    private readonly Stopwatch playbackClock = new();
    private double playbackElapsed;
    private int playbackFrameIndex = -1;
    private AnimationClip? playbackClip;
    private bool playbackPaused;
    private bool changingPlaybackSelection;
    private bool measuringTimerPrecision;
    private readonly List<double> timerTickIntervalsMs = [];
    private long previousTimerTick;
    private AnimationDocument document = new();
    private AnimationClip Clip => document.Clips[Math.Clamp(clipSelect.SelectedIndex, 0, document.Clips.Count - 1)];
    private string workspacePath = "";
    private bool updating;
    private readonly string? acceptancePath;
    private System.Windows.Forms.Timer? acceptanceTimer;
    internal int ExitCode { get; private set; }

    public AnimationWorkspaceForm(string? acceptancePath = null)
    {
        this.acceptancePath = acceptancePath;
        Text = "BeltScroll · 캐릭터 아트 / 애니메이션 작업공간";
        Width = 1360; Height = 900; MinimumSize = new Size(1040, 700); StartPosition = FormStartPosition.CenterParent;
        workspacePath = Path.Combine(Path.GetTempPath(), "BeltScrollAnimationWorkspace", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(workspacePath, "textures"));
        document.Clips.Add(new AnimationClip());

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(8), ColumnCount = 2, RowCount = 3 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290)); root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 46)); root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        var top = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, AutoScroll = true };
        top.Controls.Add(new Label { Text = "클립", AutoSize = true, Padding = new Padding(4, 8, 2, 0) }); top.Controls.Add(clipSelect);
        AddButton(top, "새 클립", AddClip); AddButton(top, "클립 삭제", RemoveClip);
        top.Controls.Add(new Label { Text = "ID", AutoSize = true, Padding = new Padding(4, 8, 2, 0) }); top.Controls.Add(clipId);
        AddButton(top, "PNG 프레임 가져오기", ImportPngs); AddButton(top, "JSON 내보내기", ExportJson); AddButton(top, "JSON 불러오기", ImportJson);
        root.Controls.Add(top, 0, 0); root.SetColumnSpan(top, 2);

        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1 };
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 65)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 35));
        left.Controls.Add(frameList, 0, 0);
        var frameButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        AddButton(frameButtons, "위로", () => MoveFrame(-1)); AddButton(frameButtons, "아래로", () => MoveFrame(1)); AddButton(frameButtons, "삭제", RemoveFrame);
        left.Controls.Add(frameButtons, 0, 1);
        var review = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new Padding(2) };
        review.RowStyles.Add(new RowStyle(SizeType.Absolute, 28)); review.RowStyles.Add(new RowStyle(SizeType.Absolute, 58)); review.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); review.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
        review.Controls.Add(new Label { Text = "수동 시각 검수 체크리스트", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
        var checklist = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = true, AutoScroll = true }; foreach (var check in reviewChecks) checklist.Controls.Add(check); review.Controls.Add(checklist, 0, 1); review.Controls.Add(reviewComment, 0, 2);
        var reviewActions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        reviewOpinion.Items.AddRange(["보류", "반려", "승인"]); reviewOpinion.SelectedIndex = 0;
        reviewActions.Controls.Add(reviewOpinion); AddButton(reviewActions, "의견 내보내기", ExportReviewOpinion); review.Controls.Add(reviewActions, 0, 3);
        left.Controls.Add(review, 0, 2); root.Controls.Add(left, 0, 1);

        var right = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 2, Padding = new Padding(6, 0, 0, 0) };
        right.RowStyles.Add(new RowStyle(SizeType.Absolute, 34)); right.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); right.RowStyles.Add(new RowStyle(SizeType.Absolute, 54));
        right.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50)); right.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        right.Controls.Add(new Label { Text = "좌우 프리뷰 · 투명 격자 · 실루엣 경계", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter }, 0, 0);
        right.Controls.Add(new Label { Text = "미러 프리뷰", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter }, 1, 0);
        right.Controls.Add(preview, 0, 1); right.Controls.Add(leftPreview, 1, 1);
        var edit = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, AutoScroll = true, Padding = new Padding(0, 8, 0, 0) };
        edit.Controls.Add(new Label { Text = "페이즈", AutoSize = true, Padding = new Padding(2, 6, 0, 0) });
        phase.Items.AddRange(["startup", "inbetween", "contact", "recovery"]); phase.SelectedIndex = 0; edit.Controls.Add(phase);
        edit.Controls.Add(new Label { Text = "지속시간(초)", AutoSize = true, Padding = new Padding(8, 6, 0, 0) }); edit.Controls.Add(duration);
        approval.Items.AddRange(["review", "approved", "unapproved", "temporary"]); approval.SelectedItem = "review";
        edit.Controls.Add(new Label { Text = "검수 상태", AutoSize = true, Padding = new Padding(8, 6, 0, 0) }); edit.Controls.Add(approval);
        AddButton(edit, "재생", StartPlayback); AddButton(edit, "정지", () => StopPlayback()); edit.Controls.Add(intermediatePlayback);
        right.Controls.Add(edit, 0, 2); right.SetColumnSpan(edit, 2);
        var frameTab = new TabPage("프레임 미리보기"); frameTab.Controls.Add(right);
        var compareTab = new TabPage("원화 3× 비교"); compareTab.Controls.Add(comparisonPanel);
        previewTabs.TabPages.Add(frameTab); previewTabs.TabPages.Add(compareTab); root.Controls.Add(previewTabs, 1, 1);
        root.Controls.Add(status, 0, 2); root.SetColumnSpan(status, 2); Controls.Add(root);

        clipSelect.SelectedIndexChanged += (_, _) => { if (!updating && clipSelect.SelectedIndex >= 0) { StopPlayback(false); updating = true; clipId.Text = Clip.Id; updating = false; SetPhaseOptions(); RefreshFrames(0); } };
        clipSelect.Items.Add("attack1"); clipSelect.SelectedIndex = 0;
        frameList.SelectedIndexChanged += (_, _) => { SelectFrame(); if (!changingPlaybackSelection && (playback.Enabled || playbackPaused)) RebasePlaybackToSelection(); };
        phase.SelectedIndexChanged += (_, _) => UpdateFrame(); duration.ValueChanged += (_, _) => UpdateFrame(); approval.SelectedIndexChanged += (_, _) => UpdateFrame();
        clipId.TextChanged += (_, _) => RenameClip();
        preview.AnchorChanged += (_, point) => { if (CurrentFrame is { } f) { f.FootAnchor = new FootAnchor { X = point.X, Y = point.Y }; preview.Invalidate(); leftPreview.Invalidate(); SetStatus($"발 anchor: ({point.X:0.000}, {point.Y:0.000})"); } };
        playback.Tick += (_, _) => OnPlaybackTick();
        intermediatePlayback.CheckedChanged += (_, _) => { if (playback.Enabled || playbackPaused) RefreshPlaybackPreview(); };
        FormClosed += (_, _) => { playback.Stop(); playbackClock.Stop(); preview.DisposeImage(); leftPreview.DisposeImage(); };
        SetStatus($"별도 임시 작업 폴더: {workspacePath}");
        if (acceptancePath is not null)
        {
            Directory.CreateDirectory(acceptancePath);
            acceptanceTimer = new System.Windows.Forms.Timer { Interval = 120 };
            acceptanceTimer.Tick += (_, _) => RunGuiAcceptance();
            Shown += (_, _) => acceptanceTimer.Start();
        }
    }

    private AnimationFrame? CurrentFrame => frameList.SelectedIndex is >= 0 and var i && i < Clip.Frames.Count ? Clip.Frames[i] : null;

    private static readonly string[] ValidClipIds = ["idle", "attack1", "attack2", "attack3"];
    private void AddClip()
    {
        string? id = ValidClipIds.FirstOrDefault(x => document.Clips.All(c => c.Id != x));
        if (id is null) { SetStatus("idle, attack1~3 클립이 모두 있습니다."); return; }
        document.Clips.Add(new AnimationClip { Id = id }); RefreshClipSelector(id); SetStatus($"{id} 클립을 만들었습니다.");
    }
    private void RemoveClip()
    {
        if (document.Clips.Count <= 1) { SetStatus("최소 한 개의 클립이 필요합니다."); return; }
        int i = clipSelect.SelectedIndex; document.Clips.RemoveAt(i); RefreshClipSelector(document.Clips[Math.Max(0, i - 1)].Id);
    }
    private void RenameClip()
    {
        if (updating || clipSelect.SelectedIndex < 0) return;
        string id = clipId.Text.Trim();
        if (!ValidClipIds.Contains(id) || document.Clips.Any(c => !ReferenceEquals(c, Clip) && c.Id == id)) { SetStatus("클립 ID는 idle, attack1, attack2, attack3 중 중복 없이 선택해야 합니다."); return; }
        Clip.Id = id; int index = clipSelect.SelectedIndex; updating = true; clipSelect.Items[index] = id; clipSelect.SelectedIndex = index; updating = false;
    }
    private void RefreshClipSelector(string selectedId)
    {
        StopPlayback(false); updating = true; clipSelect.Items.Clear(); foreach (var c in document.Clips) clipSelect.Items.Add(c.Id);
        clipSelect.SelectedIndex = Math.Max(0, document.Clips.FindIndex(c => c.Id == selectedId)); clipId.Text = Clip.Id; updating = false; SetPhaseOptions(); RefreshFrames(0);
    }
    private void SetPhaseOptions()
    {
        string[] options = Clip.Id == "idle" ? ["idle"] : ["startup", "inbetween", "contact", "recovery"];
        updating = true; phase.Items.Clear(); phase.Items.AddRange(options); updating = false;
    }

    private void ImportPngs()
    {
        using var dialog = new OpenFileDialog { Title = "애니메이션 PNG 프레임 가져오기", Filter = "PNG 이미지 (*.png)|*.png", Multiselect = true };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        AddPngFiles(dialog.FileNames);
    }

    private void AddPngFiles(IEnumerable<string> files)
    {
        int count = 0;
        foreach (string source in files)
        {
            using var check = Image.FromFile(source);
            if (check.Width <= 0 || check.Height <= 0) continue;
            string name = $"{Guid.NewGuid():N}.png"; string destination = Path.Combine(workspacePath, "textures", name);
            File.Copy(source, destination, true);
            Clip.Frames.Add(new AnimationFrame { Texture = Path.Combine("textures", name).Replace('\\', '/'), Phase = Clip.Id == "idle" ? "idle" : "startup", Duration = 0.1, FootAnchor = new FootAnchor { X = 0.5, Y = 0.92 }, ApprovalState = "review" });
            count++;
        }
        RefreshFrames(Clip.Frames.Count - 1); SetStatus($"PNG {count}개를 가져왔습니다. 새 프레임은 모두 review 상태입니다.");
    }

    private void ExportJson()
    {
        Clip.Id = string.IsNullOrWhiteSpace(clipId.Text) ? "clip" : clipId.Text.Trim();
        try { ValidateDocument(document); } catch (InvalidDataException e) { SetStatus("내보내기 거부: " + e.Message); return; }
        using var dialog = new FolderBrowserDialog { Description = "별도 임시 애니메이션 작업 폴더 선택", SelectedPath = workspacePath, ShowNewFolderButton = true };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        ExportTo(dialog.SelectedPath);
    }

    private void ExportTo(string destinationFolder)
    {
        string sourceRoot = workspacePath;
        workspacePath = Path.GetFullPath(destinationFolder); Directory.CreateDirectory(Path.Combine(workspacePath, "textures"));
        foreach (var frame in document.Clips.SelectMany(c => c.Frames))
        {
            if (string.IsNullOrWhiteSpace(frame.Texture)) continue;
            string source = Path.GetFullPath(Path.Combine(sourceRoot, frame.Texture.Replace('/', Path.DirectorySeparatorChar)));
            if (!File.Exists(source)) { SetStatus($"텍스처가 없습니다: {frame.Texture}"); return; }
            string relative = frame.Texture.Replace('/', Path.DirectorySeparatorChar);
            string target = Path.GetFullPath(Path.Combine(workspacePath, relative));
            if (!target.StartsWith(Path.GetFullPath(workspacePath) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) { SetStatus("텍스처 경로가 작업 폴더 밖을 가리킵니다."); return; }
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            if (!string.Equals(Path.GetFullPath(source), target, StringComparison.OrdinalIgnoreCase)) File.Copy(source, target, true);
        }
        File.WriteAllText(Path.Combine(workspacePath, "animation.json"), JsonSerializer.Serialize(document, JsonOptions), new UTF8Encoding(false));
        SetStatus($"내보냄: {Path.Combine(workspacePath, "animation.json")} · 승인 안 된 프레임은 review로 저장");
    }

    private void ImportJson()
    {
        using var dialog = new OpenFileDialog { Title = "애니메이션 작업 JSON 불러오기", Filter = "JSON 파일 (*.json)|*.json" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { LoadJson(dialog.FileName); }
        catch (Exception ex) when (ex is IOException or JsonException or InvalidDataException or ArgumentException)
        { SetStatus("불러오기 오류: " + ex.Message); }
    }

    private void LoadJson(string jsonPath)
    {
        try
        {
            var loaded = JsonSerializer.Deserialize<AnimationDocument>(File.ReadAllText(jsonPath, Encoding.UTF8), JsonOptions) ?? throw new InvalidDataException("문서를 읽을 수 없습니다.");
            ValidateDocument(loaded);
            string root = Path.GetDirectoryName(Path.GetFullPath(jsonPath))!;
            foreach (var f in loaded.Clips.SelectMany(c => c.Frames).Where(f => !string.IsNullOrWhiteSpace(f.Texture)))
            {
                string texture = Path.GetFullPath(Path.Combine(root, f.Texture!.Replace('/', Path.DirectorySeparatorChar)));
                if (!texture.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(texture)) throw new InvalidDataException($"텍스처 파일을 찾을 수 없습니다: {f.Texture}");
                using var image = Image.FromFile(texture);
            }
            document = loaded; workspacePath = root; RefreshClipSelector(loaded.Clips[0].Id);
            SetStatus($"불러옴: {jsonPath}");
        }
        catch { throw; }
    }

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
    internal static void ValidateDocument(AnimationDocument doc)
    {
        if (doc.SchemaVersion != 1 || doc.Clips is null || doc.Clips.Count == 0) throw new InvalidDataException("schema_version=1과 하나 이상의 clips가 필요합니다.");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var clip in doc.Clips)
        {
            if (clip.Id is null || !new[] { "idle", "attack1", "attack2", "attack3" }.Contains(clip.Id) || !ids.Add(clip.Id) || clip.Frames is null || clip.Frames.Count == 0) throw new InvalidDataException("클립 ID는 idle, attack1, attack2, attack3 중 중복 없이 지정하고 하나 이상의 프레임이 있어야 합니다.");
            foreach (var f in clip.Frames)
            {
                if (f.Phase is not ("idle" or "startup" or "inbetween" or "contact" or "recovery") || (clip.Id == "idle" ? f.Phase != "idle" : f.Phase == "idle")) throw new InvalidDataException("클립 ID에 맞는 phase를 지정해야 합니다.");
                if (f.Texture is not null && !IsSafeRelativeTexture(f.Texture)) throw new InvalidDataException("texture는 작업 폴더 기준 상대 경로여야 합니다.");
                if (double.IsNaN(f.Duration) || double.IsInfinity(f.Duration) || f.Duration <= 0 || f.Duration > 10) throw new InvalidDataException("duration은 0 초과 10초 이하여야 합니다.");
                if (f.FootAnchor is null || double.IsNaN(f.FootAnchor.X) || double.IsNaN(f.FootAnchor.Y) || f.FootAnchor.X < 0 || f.FootAnchor.X > 1 || f.FootAnchor.Y < 0 || f.FootAnchor.Y > 1) throw new InvalidDataException("foot_anchor는 이미지 안의 0~1 좌표여야 합니다.");
                if (f.ApprovalState is not ("review" or "approved" or "unapproved" or "temporary")) throw new InvalidDataException("approval_state는 review, approved, unapproved, temporary 중 하나여야 합니다.");
            }
        }
    }

    private static bool IsSafeRelativeTexture(string texture)
    {
        if (string.IsNullOrWhiteSpace(texture) || Path.IsPathRooted(texture) || texture.Contains(':') || texture.Contains('\\')) return false;
        return !texture.Split('/').Any(segment => segment is "" or "." or "..");
    }

    internal static void ContractSelfTest()
    {
        var valid = new AnimationDocument { Clips = [new AnimationClip { Id = "attack1", Frames = [new AnimationFrame { Texture = "textures/frame.png" }] }] };
        ValidateDocument(valid);
        bool legacyAnchorRejected = false;
        try { JsonSerializer.Deserialize<AnimationDocument>("""{"schema_version":1,"clips":[{"id":"attack1","frames":[{"phase":"contact","duration":0.1,"texture":null,"foot_anchor":"alpha_bottom_center","approval_state":"review"}]}]}""", JsonOptions); }
        catch (JsonException) { legacyAnchorRejected = true; }
        if (!legacyAnchorRejected) throw new InvalidOperationException("Schema v1 accepted the legacy string foot_anchor.");
        bool emptyClipRejected = false;
        try { ValidateDocument(new AnimationDocument { Clips = [new AnimationClip { Id = "attack1" }] }); }
        catch (InvalidDataException) { emptyClipRejected = true; }
        if (!emptyClipRejected) throw new InvalidOperationException("An empty clip that runtime rejects was accepted for export.");
        foreach (string unsafePath in new[] { "../outside.png", "textures/../outside.png", "res://assets/frame.png", "C:/outside.png", "textures\\frame.png" })
        {
            bool rejected = false;
            try { ValidateDocument(new AnimationDocument { Clips = [new AnimationClip { Id = "attack1", Frames = [new AnimationFrame { Texture = unsafePath }] }] }); }
            catch (InvalidDataException) { rejected = true; }
            if (!rejected) throw new InvalidOperationException($"Unsafe texture path was accepted: {unsafePath}");
        }
        var serialized = JsonSerializer.Serialize(valid, JsonOptions);
        if (!serialized.Contains("\"foot_anchor\": {", StringComparison.Ordinal)) throw new InvalidOperationException("Schema v1 anchor did not serialize as an x/y object.");
    }

    private string ResolveTexture(string relative) => Path.GetFullPath(Path.Combine(workspacePath, relative.Replace('/', Path.DirectorySeparatorChar)));
    private void RefreshFrames(int select)
    {
        int index = Math.Clamp(select, Clip.Frames.Count == 0 ? 0 : 0, Math.Max(0, Clip.Frames.Count - 1));
        frameList.Items.Clear(); foreach (var f in Clip.Frames) frameList.Items.Add($"{(f.Texture is null ? "변환" : Path.GetFileName(f.Texture))} · {f.Phase} · {f.Duration:0.###}s · {f.ApprovalState}");
        frameList.SelectedIndex = Clip.Frames.Count == 0 ? -1 : index;
    }
    private void SelectFrame()
    {
        var f = CurrentFrame; updating = true;
        if (f is null) { preview.SetImage(null, null); leftPreview.SetImage(null, null); comparisonPanel.SetCurrentFrame(null, null, 0); phase.SelectedIndex = -1; approval.SelectedIndex = -1; }
        else
        {
            phase.SelectedItem = f.Phase; duration.Value = Math.Clamp((decimal)f.Duration, duration.Minimum, duration.Maximum); approval.SelectedItem = f.ApprovalState;
            string? path = f.Texture is null ? null : ResolveTexture(f.Texture);
            preview.SetImage(path, f.FootAnchor); leftPreview.SetImage(path, f.FootAnchor);
            comparisonPanel.SetCurrentFrame(path, f.FootAnchor, f.Duration, $"{Clip.Id} · 프레임 {frameList.SelectedIndex + 1}");
        }
        updating = false;
    }
    private void UpdateFrame()
    {
        if (updating || CurrentFrame is not { } f) return;
        f.Phase = phase.SelectedItem?.ToString() ?? (Clip.Id == "idle" ? "idle" : "startup");
        f.Duration = (double)duration.Value; f.ApprovalState = approval.SelectedItem?.ToString() ?? "review";
        comparisonPanel.SetCurrentFrame(f.Texture is null ? null : ResolveTexture(f.Texture), f.FootAnchor, f.Duration, $"{Clip.Id} · 프레임 {frameList.SelectedIndex + 1}");
        int index = frameList.SelectedIndex; RefreshFrames(index); SetStatus(f.ApprovalState == "approved" ? "편집 데이터에 approved로 표시했습니다. 게임 사용은 런타임 allowlist 검증이 별도로 적용됩니다." : $"approval_state={f.ApprovalState}");
    }
    private void MoveFrame(int delta)
    {
        int old = frameList.SelectedIndex, next = old + delta; if (old < 0 || next < 0 || next >= Clip.Frames.Count) return;
        (Clip.Frames[old], Clip.Frames[next]) = (Clip.Frames[next], Clip.Frames[old]);
        changingPlaybackSelection = true; RefreshFrames(next); changingPlaybackSelection = false;
        if (playback.Enabled || playbackPaused) { playbackFrameIndex = next; playbackClip = Clip; RefreshPlaybackPreview(); }
    }
    private void RemoveFrame()
    {
        int i = frameList.SelectedIndex; if (i < 0) return;
        Clip.Frames.RemoveAt(i); RefreshFrames(Math.Max(0, i - 1));
    }
    private void StartPlayback()
    {
        if (Clip.Frames.Count == 0) return;
        if (playback.Enabled)
        {
            double elapsed = playbackClock.Elapsed.TotalSeconds;
            playback.Stop(); playbackClock.Reset();
            if (elapsed > 0) AdvancePlaybackBy(elapsed);
            playbackPaused = true;
            SetStatus("재생 일시정지 · 재생 버튼으로 이어서 재생"); return;
        }
        if (playbackPaused && ReferenceEquals(playbackClip, Clip) && playbackFrameIndex >= 0)
        {
            playbackClock.Restart(); playback.Start(); playbackPaused = false;
            SetStatus(intermediatePlayback.Checked ? "애니메이션 재개 · 실측 시간 기반 중간동작" : "애니메이션 재개 · 실측 시간 기반"); return;
        }
        if (frameList.SelectedIndex < 0) frameList.SelectedIndex = 0;
        playbackClip = Clip; playbackFrameIndex = frameList.SelectedIndex; playbackElapsed = 0; playbackPaused = false;
        playbackClock.Restart(); playback.Start();
        SetStatus(intermediatePlayback.Checked ? "애니메이션 재생 중 · 실측 시간 기반 중간동작" : "애니메이션 재생 중 · 실측 시간 기반");
    }
    private void StopPlayback(bool updateStatus = true)
    {
        playback.Stop(); playbackClock.Reset(); playbackPaused = false; playbackFrameIndex = -1; playbackClip = null; playbackElapsed = 0;
        preview.SetBlendImages(null, null, null, 0); leftPreview.SetBlendImages(null, null, null, 0);
        if (updateStatus) SetStatus("재생 정지");
    }
    private void OnPlaybackTick()
    {
        long now = Stopwatch.GetTimestamp();
        if (measuringTimerPrecision)
        {
            if (previousTimerTick != 0) timerTickIntervalsMs.Add((now - previousTimerTick) * 1000d / Stopwatch.Frequency);
            previousTimerTick = now; return;
        }
        if (Clip.Frames.Count == 0 || !ReferenceEquals(playbackClip, Clip)) { StopPlayback(); return; }
        double elapsed = playbackClock.Elapsed.TotalSeconds;
        playbackClock.Restart();
        AdvancePlaybackBy(elapsed);
    }
    private void AdvancePlaybackBy(double elapsedSeconds)
    {
        if (Clip.Frames.Count == 0 || playbackFrameIndex < 0 || playbackFrameIndex >= Clip.Frames.Count) { StopPlayback(); return; }
        playbackElapsed += Math.Max(0, elapsedSeconds);
        int guard = 0;
        while (guard++ < 100000)
        {
            double frameDuration = Math.Max(0.001, Clip.Frames[playbackFrameIndex].Duration);
            if (playbackElapsed + 0.000000001 < frameDuration) break;
            playbackElapsed -= frameDuration;
            playbackFrameIndex = (playbackFrameIndex + 1) % Clip.Frames.Count;
        }
        changingPlaybackSelection = true;
        if (frameList.SelectedIndex != playbackFrameIndex) frameList.SelectedIndex = playbackFrameIndex;
        changingPlaybackSelection = false;
        RefreshPlaybackPreview();
    }
    private void RefreshPlaybackPreview()
    {
        if (Clip.Frames.Count == 0 || playbackFrameIndex < 0) return;
        var current = Clip.Frames[playbackFrameIndex];
        if (!intermediatePlayback.Checked || Clip.Frames.Count < 2)
        {
            preview.SetBlendImages(null, null, null, 0); leftPreview.SetBlendImages(null, null, null, 0); return;
        }
        var next = Clip.Frames[(playbackFrameIndex + 1) % Clip.Frames.Count];
        double mix = Math.Clamp(playbackElapsed / Math.Max(0.001, current.Duration), 0, 1);
        string? firstPath = current.Texture is null ? null : ResolveTexture(current.Texture);
        string? nextPath = next.Texture is null ? null : ResolveTexture(next.Texture);
        preview.SetBlendImages(firstPath, nextPath, current.FootAnchor, mix);
        leftPreview.SetBlendImages(firstPath, nextPath, current.FootAnchor, mix);
    }
    private void RebasePlaybackToSelection()
    {
        playbackFrameIndex = frameList.SelectedIndex; playbackElapsed = 0; playbackClip = Clip;
        if (playbackClock.IsRunning) playbackClock.Restart();
        RefreshPlaybackPreview();
    }

    private void ExportReviewOpinion()
    {
        if (acceptancePath is not null) { SetStatus("자동 GUI 검수에서는 사람의 승인 의견 내보내기가 비활성화됩니다."); return; }
        var frame = CurrentFrame; if (frame is null) { SetStatus("의견을 내보낼 프레임을 선택하세요."); return; }
        using var dialog = new SaveFileDialog { Title = "수동 시각 검수 의견 내보내기", Filter = "검수 의견 JSON (*.json)|*.json", FileName = $"{Clip.Id}-frame-{frameList.SelectedIndex + 1}-review.json", DefaultExt = "json" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        var report = new { schema_version = 1, clip_id = Clip.Id, frame_index = frameList.SelectedIndex, texture = frame.Texture, opinion = reviewOpinion.SelectedItem?.ToString() ?? "보류", checklist = new { face = reviewChecks[0].Checked, ears = reviewChecks[1].Checked, costume = reviewChecks[2].Checked, supporting_foot = reviewChecks[3].Checked, motion_connection = reviewChecks[4].Checked }, comment = reviewComment.Text, exported_at = DateTimeOffset.Now.ToString("O"), approval_state_changed = false, game_allowlist_changed = false };
        File.WriteAllText(dialog.FileName, JsonSerializer.Serialize(report, JsonOptions), new UTF8Encoding(false));
        SetStatus($"사람 검수 의견을 내보냈습니다: {dialog.FileName} · 프레임 approval_state와 게임 allowlist는 변경하지 않았습니다.");
    }
    private void SetStatus(string text) => status.Text = text;
    private object MeasureTimerPrecision()
    {
        playback.Stop(); playbackClock.Reset(); timerTickIntervalsMs.Clear(); previousTimerTick = 0;
        playback.Interval = 10; measuringTimerPrecision = true; playback.Start();
        var timeout = Stopwatch.StartNew();
        try
        {
            while (timerTickIntervalsMs.Count < 40 && timeout.Elapsed < TimeSpan.FromSeconds(4))
            {
                Application.DoEvents(); Thread.Sleep(1);
            }
        }
        finally { playback.Stop(); measuringTimerPrecision = false; }
        if (timerTickIntervalsMs.Count < 10) throw new Exception($"WinForms timer precision sample was too short ({timerTickIntervalsMs.Count} intervals).");
        double[] sorted = timerTickIntervalsMs.Order().ToArray();
        return new { requestedIntervalMs = playback.Interval, sampleCount = sorted.Length, minMs = Math.Round(sorted[0], 3), medianMs = Math.Round(sorted[sorted.Length / 2], 3), meanMs = Math.Round(sorted.Average(), 3), maxMs = Math.Round(sorted[^1], 3), measuredAt = DateTimeOffset.Now.ToString("O") };
    }
    private void RunGuiAcceptance()
    {
        acceptanceTimer?.Stop();
        try
        {
            string fixture = Path.Combine(acceptancePath!, "fixture.png");
            using (var bitmap = new Bitmap(24, 32))
            using (var graphics = Graphics.FromImage(bitmap)) { graphics.Clear(Color.Transparent); using var brush = new SolidBrush(Color.CornflowerBlue); graphics.FillEllipse(brush, 4, 3, 16, 28); bitmap.Save(fixture, System.Drawing.Imaging.ImageFormat.Png); }
            AddPngFiles([fixture]);
            if (Clip.Frames.Count != 1 || Clip.Frames[0].ApprovalState != "review") throw new Exception("Imported frame was not added in review state.");
            phase.SelectedItem = "startup"; duration.Value = 0.075M; approval.SelectedItem = "review";
            preview.SimulateClick(new Point(preview.Width / 2, preview.Height / 2));
            if (Math.Abs(Clip.Frames[0].FootAnchor.Y - 0.5) > 0.02) throw new Exception("Anchor pointer event did not update the foot anchor.");
            foreach (string p in new[] { "inbetween", "contact", "recovery" }) AddPngFiles([fixture]);
            string[] phases = ["startup", "inbetween", "contact", "recovery"];
            string[] states = ["review", "review", "review", "review"];
            decimal[] times = [0.035M, 0.05M, 0.105M, 0.2M];
            for (int i = 0; i < phases.Length; i++) { frameList.SelectedIndex = i; phase.SelectedItem = phases[i]; duration.Value = times[i]; approval.SelectedItem = states[i]; }
            if (!Clip.Frames.Select(f => f.Duration).SequenceEqual(new[] { .035, .05, .105, .2 })) throw new Exception("35/50/105/200ms frame durations were not stored in timeline order.");
            frameList.SelectedIndex = 2; ((Button)FindControl(this, "위로")).PerformClick();
            if (frameList.SelectedIndex != 1 || Clip.Frames[1].Phase != "contact" || !Clip.Frames.Select(f => f.Duration).SequenceEqual(new[] { .035, .105, .05, .2 })) throw new Exception("Frame reorder did not preserve each frame's duration and order.");
            ((Button)FindControl(this, "아래로")).PerformClick();
            AddClip(); AddClip(); AddClip();
            if (!document.Clips.Select(c => c.Id).OrderBy(x => x).SequenceEqual(new[] { "attack1", "attack2", "attack3", "idle" }.OrderBy(x => x))) throw new Exception("Creating all supported clip IDs failed.");
            foreach (string id in new[] { "attack2", "attack3" }) { clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == id); AddPngFiles([fixture]); }
            clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == "idle"); AddPngFiles([fixture]);
            if (Clip.Frames.Single().Phase != "idle" || Clip.Frames.Single().ApprovalState != "review") throw new Exception("Idle clip frame contract/default review state failed.");
            clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == "attack1");
            intermediatePlayback.Checked = true;
            string comparisonFixture = Path.Combine(acceptancePath!, "comparison.png");
            using (var bitmap = new Bitmap(24, 32)) using (var graphics = Graphics.FromImage(bitmap)) { graphics.Clear(Color.Transparent); using var brush = new SolidBrush(Color.OrangeRed); graphics.FillRectangle(brush, 2, 8, 20, 18); bitmap.Save(comparisonFixture, System.Drawing.Imaging.ImageFormat.Png); }
            comparisonPanel.ConfigureForAcceptance(comparisonFixture);
            frameList.SelectedIndex = 0;
            comparisonPanel.SetCurrentFrame(ResolveTexture(Clip.Frames[0].Texture!), new FootAnchor { X = 0.5, Y = 0.92 }, Clip.Frames[0].Duration, "attack1 · 검수 anchor 하단 위치");
            var comparisonEvents = comparisonPanel.ExerciseAcceptance(acceptancePath!);
            ((Button)FindControl(this, "재생")).PerformClick(); if (!playback.Enabled || playback.Interval != 10) throw new Exception("Playback did not start with the fixed 10ms UI refresh trigger.");
            playbackFrameIndex = 0; playbackElapsed = 0;
            AdvancePlaybackBy(.034); if (playbackFrameIndex != 0) throw new Exception("The 35ms frame advanced before its cumulative duration elapsed.");
            AdvancePlaybackBy(.001); if (playbackFrameIndex != 1 || Math.Abs(playbackElapsed) > .000001) throw new Exception("The 35ms frame boundary was not measured accurately.");
            AdvancePlaybackBy(.05); if (playbackFrameIndex != 2) throw new Exception("The 50ms frame duration boundary failed.");
            AdvancePlaybackBy(.105); if (playbackFrameIndex != 3) throw new Exception("The 105ms frame duration boundary failed.");
            AdvancePlaybackBy(.2); if (playbackFrameIndex != 0) throw new Exception("The 200ms duration or loop boundary failed.");
            AdvancePlaybackBy(.39); if (playbackFrameIndex != 0 || Math.Abs(playbackElapsed) > .000001) throw new Exception("A full 390ms loop did not return to its exact starting position.");
            AdvancePlaybackBy(.025); if (!preview.BlendVisible) throw new Exception("Measured-time intermediate frame blend was not rendered.");
            ((Button)FindControl(this, "재생")).PerformClick(); if (playback.Enabled || !playbackPaused) throw new Exception("Playback did not pause cleanly.");
            double pausedPosition = playbackElapsed; ((Button)FindControl(this, "재생")).PerformClick(); if (!playback.Enabled || Math.Abs(playbackElapsed - pausedPosition) > .000001) throw new Exception("Resume did not preserve the playback position.");
            ((Button)FindControl(this, "정지")).PerformClick();
            var timerPrecision = MeasureTimerPrecision();
            ((Button)FindControl(this, "재생")).PerformClick();
            previewTabs.SelectedIndex = 0;
            ((Button)FindControl(this, "정지")).PerformClick(); if (playback.Enabled) throw new Exception("Playback did not stop.");
            string exported = Path.Combine(acceptancePath!, "workspace"); ExportTo(exported);
            var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(exported, "animation.json"), Encoding.UTF8)).RootElement;
            if (json.GetProperty("schema_version").GetInt32() != 1 || json.GetProperty("clips").GetArrayLength() != 4) throw new Exception("Export contract mismatch.");
            var savedPhases = json.GetProperty("clips").EnumerateArray().Single(c => c.GetProperty("id").GetString() == "attack1").GetProperty("frames").EnumerateArray().Select(f => f.GetProperty("phase").GetString()).ToArray();
            LoadJson(Path.Combine(exported, "animation.json"));
            var loadedAttack = document.Clips.Single(c => c.Id == "attack1");
            if (!loadedAttack.Frames.Select(f => f.Phase).SequenceEqual(savedPhases) || loadedAttack.Frames.Count != 4 || loadedAttack.Frames.Any(f => f.ApprovalState != "review") || Math.Abs(loadedAttack.Frames[3].Duration - .2) > .001 || Math.Abs(loadedAttack.Frames[0].FootAnchor.Y - .5) > .02) throw new Exception("JSON reload did not preserve frame order, duration, anchor or review-only state.");
            if (!document.Clips.Select(c => c.Id).OrderBy(x => x).SequenceEqual(new[] { "idle", "attack1", "attack2", "attack3" }.OrderBy(x => x))) throw new Exception("JSON reload lost clip IDs.");
            if (document.Clips.Single(c => c.Id == "idle").Frames.Single().Phase != "idle") throw new Exception("JSON reload lost idle phase.");
            previewTabs.SelectedIndex = 1;
            using var capture = new Bitmap(Math.Max(1, Width), Math.Max(1, Height)); DrawToBitmap(capture, new Rectangle(Point.Empty, capture.Size)); capture.Save(Path.Combine(acceptancePath!, "animation-gui.png"), System.Drawing.Imaging.ImageFormat.Png);
            var report = new { passed = true, guiMessageLoop = true, guiControlEvents = new[] { "PNG import", "clip creation and selection", "four phase selection", "duration edit", "anchor pointer event", "frame reorder with duration identity", "35ms/50ms/105ms/200ms cumulative playback", "loop boundary", "pause and resume position", "slow tick catch-up", "10ms UI refresh trigger", "measured WinForms timer precision", "play", "stop", "multi-clip JSON export", "JSON reload" }.Concat(comparisonEvents).ToArray(), timerPrecision, schemaVersion = 1, exportedPath = Path.Combine(exported, "animation.json"), clipCount = document.Clips.Count, frameCount = loadedAttack.Frames.Count, approvalState = "review", approvalDecisionCreated = false, gameAllowlistChanged = false, workspacePath = exported };
            File.WriteAllText(Path.Combine(acceptancePath!, "animation-gui-acceptance.json"), JsonSerializer.Serialize(report, JsonOptions), new UTF8Encoding(false));
            ExitCode = 0; Close();
        }
        catch (Exception ex)
        {
            ExitCode = 1; File.WriteAllText(Path.Combine(acceptancePath!, "animation-gui-acceptance.json"), JsonSerializer.Serialize(new { passed = false, error = ex.ToString() }, JsonOptions), new UTF8Encoding(false)); Close();
        }
    }
    private static Control FindControl(Control root, string label) => root.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c))).OfType<Button>().First(b => b.Text == label);
    private static IEnumerable<Control> Descendants(Control root) => root.Controls.Cast<Control>().SelectMany(c => new[] { c }.Concat(Descendants(c)));
    private static void AddButton(Control parent, string label, Action action) { var b = new Button { Text = label, AutoSize = true, Margin = new Padding(3) }; b.Click += (_, _) => action(); parent.Controls.Add(b); }
}

internal sealed class PicturePreview : Control
{
    private Image? image;
    private Image? blendImage;
    private string? imagePath;
    private string? blendImagePath;
    private float blendOpacity;
    internal bool BlendVisible => blendImage is not null && blendOpacity > 0;
    private FootAnchor? anchor;
    public bool Mirror { get; set; }
    public event EventHandler<PointF>? AnchorChanged;
    public PicturePreview() { DoubleBuffered = true; ResizeRedraw = true; SetStyle(ControlStyles.Selectable, true); }
    public void DisposeImage() { image?.Dispose(); blendImage?.Dispose(); image = null; blendImage = null; imagePath = null; blendImagePath = null; }
    public void SetImage(string? path, FootAnchor? value)
    {
        LoadPrimary(path); blendImage?.Dispose(); blendImage = null; blendImagePath = null; blendOpacity = 0; anchor = value is null ? null : new FootAnchor { X = value.X, Y = value.Y };
        Invalidate();
    }
    public void SetBlendImages(string? firstPath, string? nextPath, FootAnchor? value, double amount)
    {
        LoadPrimary(firstPath);
        if (!string.Equals(blendImagePath, nextPath, StringComparison.OrdinalIgnoreCase))
        {
            blendImage?.Dispose(); blendImage = null; blendImagePath = nextPath;
            if (!string.IsNullOrWhiteSpace(nextPath) && File.Exists(nextPath)) { using var stream = File.OpenRead(nextPath); using var decoded = Image.FromStream(stream); blendImage = new Bitmap(decoded); }
        }
        blendOpacity = (float)Math.Clamp(amount, 0, 1); anchor = value is null ? null : new FootAnchor { X = value.X, Y = value.Y }; Invalidate();
    }
    private void LoadPrimary(string? path)
    {
        if (string.Equals(imagePath, path, StringComparison.OrdinalIgnoreCase)) return;
        image?.Dispose(); image = null; imagePath = path;
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path)) { using var stream = File.OpenRead(path); using var decoded = Image.FromStream(stream); image = new Bitmap(decoded); }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e); var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        const int cell = 16;
        using var a = new SolidBrush(Color.FromArgb(62, 66, 74)); using var b = new SolidBrush(Color.FromArgb(76, 80, 88));
        for (int y = 0; y < Height; y += cell) for (int x = 0; x < Width; x += cell) g.FillRectangle(((x / cell + y / cell) & 1) == 0 ? a : b, x, y, cell, cell);
        if (image is null) { TextRenderer.DrawText(g, "PNG 프레임을 가져오세요", Font, ClientRectangle, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter); return; }
        float scale = Math.Min((Width - 42f) / image.Width, (Height - 42f) / image.Height); scale = Math.Max(0.01f, scale);
        float w = image.Width * scale, h = image.Height * scale, x0 = (Width - w) / 2, y0 = (Height - h) / 2;
        var state = g.Save(); if (Mirror) { g.TranslateTransform(Width, 0); g.ScaleTransform(-1, 1); x0 = Width - (x0 + w); }
        g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half; g.DrawImage(image, x0, y0, w, h);
        if (blendImage is not null && blendOpacity > 0)
        {
            var blendState = g.Save(); if (Mirror) { g.TranslateTransform(Width, 0); g.ScaleTransform(-1, 1); }
            using var matrix = new System.Drawing.Imaging.ImageAttributes();
            var color = new System.Drawing.Imaging.ColorMatrix { Matrix33 = blendOpacity }; matrix.SetColorMatrix(color);
            g.DrawImage(blendImage, new Rectangle((int)x0, (int)y0, (int)w, (int)h), 0, 0, blendImage.Width, blendImage.Height, GraphicsUnit.Pixel, matrix); g.Restore(blendState);
        }
        DrawSilhouette(g, image, x0, y0, scale);
        if (anchor is not null) { float ax = x0 + (float)anchor.X * w, ay = y0 + (float)anchor.Y * h; using var pen = new Pen(Color.Gold, 2); g.DrawLine(pen, ax - 9, ay, ax + 9, ay); g.DrawLine(pen, ax, ay - 9, ax, ay + 9); g.DrawEllipse(pen, ax - 5, ay - 5, 10, 10); }
        g.Restore(state);
    }
    private static void DrawSilhouette(Graphics g, Image source, float x0, float y0, float scale)
    {
        using var bitmap = new Bitmap(source); int step = Math.Max(1, Math.Max(bitmap.Width, bitmap.Height) / 1000);
        using var pen = new Pen(Color.FromArgb(230, 255, 116, 83), Math.Max(1.2f, scale * step * .7f));
        for (int y = 0; y < bitmap.Height; y += step) for (int x = 0; x < bitmap.Width; x += step)
        {
            if (bitmap.GetPixel(x, y).A < 16) continue;
            bool edge = x == 0 || y == 0 || x + step >= bitmap.Width || y + step >= bitmap.Height || bitmap.GetPixel(Math.Min(bitmap.Width - 1, x + step), y).A < 16 || bitmap.GetPixel(x, Math.Min(bitmap.Height - 1, y + step)).A < 16;
            if (edge) g.DrawRectangle(pen, x0 + x * scale, y0 + y * scale, Math.Max(1, step * scale), Math.Max(1, step * scale));
        }
    }
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e); if (image is null || e.Button != MouseButtons.Left) return;
        float scale = Math.Min((Width - 42f) / image.Width, (Height - 42f) / image.Height); scale = Math.Max(.01f, scale);
        float w = image.Width * scale, h = image.Height * scale, x0 = (Width - w) / 2, y0 = (Height - h) / 2;
        if (e.X < x0 || e.X > x0 + w || e.Y < y0 || e.Y > y0 + h) return;
        float nx = Math.Clamp((e.X - x0) / w, 0, 1); if (Mirror) nx = 1 - nx;
        AnchorChanged?.Invoke(this, new PointF(nx, Math.Clamp((e.Y - y0) / h, 0, 1)));
    }
    public void SimulateClick(Point point) => OnMouseDown(new MouseEventArgs(MouseButtons.Left, 1, point.X, point.Y, 0));
}
