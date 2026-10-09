using System.Drawing.Drawing2D;
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
    private readonly ComboBox phase = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 135 };
    private readonly NumericUpDown duration = new() { DecimalPlaces = 3, Increment = 0.025M, Minimum = 0.01M, Maximum = 10, Width = 100 };
    private readonly ComboBox approval = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 112 };
    private readonly TextBox clipId = new() { Text = "attack1", Width = 110 };
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(6) };
    private readonly System.Windows.Forms.Timer playback = new() { Interval = 100 };
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
        Width = 1180; Height = 780; MinimumSize = new Size(920, 620); StartPosition = FormStartPosition.CenterParent;
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

        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1 };
        left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        left.Controls.Add(frameList, 0, 0);
        var frameButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        AddButton(frameButtons, "위로", () => MoveFrame(-1)); AddButton(frameButtons, "아래로", () => MoveFrame(1)); AddButton(frameButtons, "삭제", RemoveFrame);
        left.Controls.Add(frameButtons, 0, 1); root.Controls.Add(left, 0, 1);

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
        AddButton(edit, "재생", StartPlayback); AddButton(edit, "정지", StopPlayback);
        right.Controls.Add(edit, 0, 2); right.SetColumnSpan(edit, 2); root.Controls.Add(right, 1, 1);
        root.Controls.Add(status, 0, 2); root.SetColumnSpan(status, 2); Controls.Add(root);

        clipSelect.SelectedIndexChanged += (_, _) => { if (!updating && clipSelect.SelectedIndex >= 0) { updating = true; clipId.Text = Clip.Id; updating = false; SetPhaseOptions(); RefreshFrames(0); } };
        clipSelect.Items.Add("attack1"); clipSelect.SelectedIndex = 0;
        frameList.SelectedIndexChanged += (_, _) => SelectFrame();
        phase.SelectedIndexChanged += (_, _) => UpdateFrame(); duration.ValueChanged += (_, _) => UpdateFrame(); approval.SelectedIndexChanged += (_, _) => UpdateFrame();
        clipId.TextChanged += (_, _) => RenameClip();
        preview.AnchorChanged += (_, point) => { if (CurrentFrame is { } f) { f.FootAnchor = new FootAnchor { X = point.X, Y = point.Y }; preview.Invalidate(); leftPreview.Invalidate(); SetStatus($"발 anchor: ({point.X:0.000}, {point.Y:0.000})"); } };
        playback.Tick += (_, _) => AdvancePlayback();
        FormClosed += (_, _) => { playback.Stop(); preview.DisposeImage(); leftPreview.DisposeImage(); };
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
        updating = true; clipSelect.Items.Clear(); foreach (var c in document.Clips) clipSelect.Items.Add(c.Id);
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
        if (f is null) { preview.SetImage(null, null); leftPreview.SetImage(null, null); phase.SelectedIndex = -1; approval.SelectedIndex = -1; }
        else
        {
            phase.SelectedItem = f.Phase; duration.Value = Math.Clamp((decimal)f.Duration, duration.Minimum, duration.Maximum); approval.SelectedItem = f.ApprovalState;
            string? path = f.Texture is null ? null : ResolveTexture(f.Texture);
            preview.SetImage(path, f.FootAnchor); leftPreview.SetImage(path, f.FootAnchor);
        }
        updating = false;
    }
    private void UpdateFrame()
    {
        if (updating || CurrentFrame is not { } f) return;
        f.Phase = phase.SelectedItem?.ToString() ?? (Clip.Id == "idle" ? "idle" : "startup");
        f.Duration = (double)duration.Value; f.ApprovalState = approval.SelectedItem?.ToString() ?? "review";
        int index = frameList.SelectedIndex; RefreshFrames(index); SetStatus(f.ApprovalState == "approved" ? "편집 데이터에 approved로 표시했습니다. 게임 사용은 런타임 allowlist 검증이 별도로 적용됩니다." : $"approval_state={f.ApprovalState}");
    }
    private void MoveFrame(int delta)
    {
        int old = frameList.SelectedIndex, next = old + delta; if (old < 0 || next < 0 || next >= Clip.Frames.Count) return;
        (Clip.Frames[old], Clip.Frames[next]) = (Clip.Frames[next], Clip.Frames[old]); RefreshFrames(next);
    }
    private void RemoveFrame()
    {
        int i = frameList.SelectedIndex; if (i < 0) return;
        Clip.Frames.RemoveAt(i); RefreshFrames(Math.Max(0, i - 1));
    }
    private void StartPlayback() { if (Clip.Frames.Count == 0) return; if (frameList.SelectedIndex < 0) frameList.SelectedIndex = 0; playback.Interval = Math.Max(20, (int)(CurrentFrame!.Duration * 1000)); playback.Start(); SetStatus("애니메이션 재생 중 · 정지 버튼으로 멈춤"); }
    private void StopPlayback() { playback.Stop(); SetStatus("재생 정지"); }
    private void AdvancePlayback() { if (Clip.Frames.Count == 0) { StopPlayback(); return; } int next = (frameList.SelectedIndex + 1) % Clip.Frames.Count; frameList.SelectedIndex = next; playback.Interval = Math.Max(20, (int)(CurrentFrame!.Duration * 1000)); }
    private void SetStatus(string text) => status.Text = text;
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
            string[] states = ["review", "temporary", "approved", "unapproved"];
            decimal[] times = [0.075M, 0.035M, 0.105M, 0.2M];
            for (int i = 0; i < phases.Length; i++) { frameList.SelectedIndex = i; phase.SelectedItem = phases[i]; duration.Value = times[i]; approval.SelectedItem = states[i]; }
            frameList.SelectedIndex = 2; ((Button)FindControl(this, "위로")).PerformClick();
            if (frameList.SelectedIndex != 1 || Clip.Frames[1].Phase != "contact") throw new Exception("Frame order controls failed.");
            AddClip(); AddClip(); AddClip();
            if (!document.Clips.Select(c => c.Id).OrderBy(x => x).SequenceEqual(new[] { "attack1", "attack2", "attack3", "idle" }.OrderBy(x => x))) throw new Exception("Creating all supported clip IDs failed.");
            foreach (string id in new[] { "attack2", "attack3" }) { clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == id); AddPngFiles([fixture]); }
            clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == "idle"); AddPngFiles([fixture]);
            if (Clip.Frames.Single().Phase != "idle" || Clip.Frames.Single().ApprovalState != "review") throw new Exception("Idle clip frame contract/default review state failed.");
            clipSelect.SelectedIndex = document.Clips.FindIndex(c => c.Id == "attack1");
            ((Button)FindControl(this, "재생")).PerformClick(); if (!playback.Enabled) throw new Exception("Playback did not start.");
            ((Button)FindControl(this, "정지")).PerformClick(); if (playback.Enabled) throw new Exception("Playback did not stop.");
            string exported = Path.Combine(acceptancePath!, "workspace"); ExportTo(exported);
            var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(exported, "animation.json"), Encoding.UTF8)).RootElement;
            if (json.GetProperty("schema_version").GetInt32() != 1 || json.GetProperty("clips").GetArrayLength() != 4) throw new Exception("Export contract mismatch.");
            var savedPhases = json.GetProperty("clips").EnumerateArray().Single(c => c.GetProperty("id").GetString() == "attack1").GetProperty("frames").EnumerateArray().Select(f => f.GetProperty("phase").GetString()).ToArray();
            LoadJson(Path.Combine(exported, "animation.json"));
            var loadedAttack = document.Clips.Single(c => c.Id == "attack1");
            if (!loadedAttack.Frames.Select(f => f.Phase).SequenceEqual(savedPhases) || loadedAttack.Frames.Count != 4 || loadedAttack.Frames[1].ApprovalState != "approved" || loadedAttack.Frames[0].ApprovalState != "review" || Math.Abs(loadedAttack.Frames[3].Duration - .2) > .001 || Math.Abs(loadedAttack.Frames[0].FootAnchor.Y - .5) > .02) throw new Exception("JSON reload did not preserve frame order, duration, anchor or approval state.");
            if (!document.Clips.Select(c => c.Id).OrderBy(x => x).SequenceEqual(new[] { "idle", "attack1", "attack2", "attack3" }.OrderBy(x => x))) throw new Exception("JSON reload lost clip IDs.");
            if (document.Clips.Single(c => c.Id == "idle").Frames.Single().Phase != "idle") throw new Exception("JSON reload lost idle phase.");
            using var capture = new Bitmap(Math.Max(1, Width), Math.Max(1, Height)); DrawToBitmap(capture, new Rectangle(Point.Empty, capture.Size)); capture.Save(Path.Combine(acceptancePath!, "animation-gui.png"), System.Drawing.Imaging.ImageFormat.Png);
            var report = new { passed = true, guiMessageLoop = true, guiControlEvents = new[] { "PNG import", "clip creation and selection", "four phase selection", "duration edit", "approval state selection", "anchor pointer event", "frame reorder", "play", "stop", "multi-clip JSON export", "JSON reload" }, schemaVersion = 1, exportedPath = Path.Combine(exported, "animation.json"), clipCount = document.Clips.Count, frameCount = loadedAttack.Frames.Count, workspacePath = exported };
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
    private FootAnchor? anchor;
    public bool Mirror { get; set; }
    public event EventHandler<PointF>? AnchorChanged;
    public PicturePreview() { DoubleBuffered = true; ResizeRedraw = true; SetStyle(ControlStyles.Selectable, true); }
    public void DisposeImage() { image?.Dispose(); image = null; }
    public void SetImage(string? path, FootAnchor? value)
    {
        image?.Dispose(); image = null; anchor = value is null ? null : new FootAnchor { X = value.X, Y = value.Y };
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path)) { using var stream = File.OpenRead(path); image = Image.FromStream(stream).Clone() as Image; }
        Invalidate();
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
