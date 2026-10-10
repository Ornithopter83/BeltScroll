using System.ComponentModel;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Diagnostics;
using System.Windows.Forms;

namespace BeltScrollEditor;

public sealed class OverrideDocument
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
    [JsonPropertyName("characters")] public List<EditorItem> Characters { get; set; } = [];
    [JsonPropertyName("enemies")] public List<EditorItem> Enemies { get; set; } = [];
    [JsonPropertyName("stages")] public List<EditorItem> Stages { get; set; } = [];
    [JsonExtensionData] public Dictionary<string, JsonElement>? ExtraFields { get; set; }
}

public sealed class EditorItem
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? Name { get; set; }
    [JsonPropertyName("max_health")] public int MaxHealth { get; set; } = 100;
    [JsonPropertyName("attack_damage")] public int AttackDamage { get; set; } = 10;
    [JsonPropertyName("walk_speed")] public double WalkSpeed { get; set; } = 1;
    [JsonPropertyName("attack_hit_stun")] public double AttackHitStun { get; set; } = 0.2;
    [JsonPropertyName("attack_knockback")] public double AttackKnockback { get; set; } = 100;
    [JsonPropertyName("attack_range")] public double AttackRange { get; set; } = 1;
    [JsonPropertyName("recovery_duration")] public double RecoveryDuration { get; set; } = 0.6;
    [JsonPropertyName("windup_duration")] public double WindupDuration { get; set; } = 0.3;
    [JsonPropertyName("active_duration")] public double ActiveDuration { get; set; } = 0.15;
    [JsonPropertyName("skill_cooldowns")] public double[] SkillCooldowns { get; set; } = [1, 1];
    [JsonPropertyName("ai")] public Dictionary<string, double> Ai { get; set; } = new() { ["notice_range"] = 500, ["attack_depth_tolerance"] = 34, ["separation_radius"] = 100, ["separation_strength"] = 100 };
    [JsonPropertyName("left")] public double Left { get; set; }
    [JsonPropertyName("top")] public double Top { get; set; }
    [JsonPropertyName("right")] public double Right { get; set; } = 1000;
    [JsonPropertyName("bottom")] public double Bottom { get; set; } = 600;
    [JsonPropertyName("player_bounds")] public Dictionary<string, double> PlayerBounds { get; set; } = new();
    [JsonPropertyName("spawns")] public List<SpawnPoint> Spawns { get; set; } = [];
    [JsonExtensionData] public Dictionary<string, JsonElement>? ExtraFields { get; set; }
    [JsonIgnore] public double X { get; set; }
    [JsonIgnore] public double Y { get; set; }
    public override string ToString() => string.IsNullOrWhiteSpace(Name) ? Id : $"{Name} ({Id})";
    public EditorItem Copy() { var copy = JsonSerializer.Deserialize<EditorItem>(JsonSerializer.Serialize(this))!; copy.X = X; copy.Y = Y; return copy; }
}

public sealed class SpawnPoint
{
    [JsonPropertyName("actor_id")] public string ActorId { get; set; } = "Player";
    [JsonPropertyName("x")] public double X { get; set; }
    [JsonPropertyName("y")] public double Y { get; set; }
    [JsonExtensionData] public Dictionary<string, JsonElement>? ExtraFields { get; set; }
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        int animationAcceptance = Array.FindIndex(args, a => a.Equals("--animation-gui-acceptance", StringComparison.OrdinalIgnoreCase));
        if (animationAcceptance >= 0 && animationAcceptance + 1 < args.Length)
        {
            ApplicationConfiguration.Initialize();
            using var workspace = new AnimationWorkspaceForm(Path.GetFullPath(args[animationAcceptance + 1]));
            Application.Run(workspace);
            return workspace.ExitCode;
        }
        if (args.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            try { SelfTest(); Console.WriteLine("BeltScrollEditor self-test passed."); return 0; }
            catch (Exception e) { Console.Error.WriteLine($"Self-test failed: {e.Message}"); return 1; }
        }
        ApplicationConfiguration.Initialize();
        string? acceptanceDir = null;
        bool runtimeRoundtrip = args.Any(a => a.Equals("--runtime-roundtrip", StringComparison.OrdinalIgnoreCase));
        bool playtestAcceptance = args.Any(a => a.Equals("--playtest-gui-acceptance", StringComparison.OrdinalIgnoreCase));
        string? playtestGodot = null;
        string? playtestRoot = null;
        for (int i = 0; i < args.Length; i++)
        {
            if ((args[i].Equals("--gui-acceptance", StringComparison.OrdinalIgnoreCase) || args[i].Equals("--playtest-gui-acceptance", StringComparison.OrdinalIgnoreCase)) && i + 1 < args.Length) acceptanceDir = Path.GetFullPath(args[++i]);
            else if (args[i].Equals("--godot", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) playtestGodot = Path.GetFullPath(args[++i]);
            else if (args[i].Equals("--project-root", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) playtestRoot = Path.GetFullPath(args[++i]);
        }
        using var form = new EditorForm(acceptanceDir, runtimeRoundtrip, playtestAcceptance, playtestGodot, playtestRoot);
        Application.Run(form);
        return form.ExitCode;
    }

    private static void SelfTest()
    {
        var doc = new OverrideDocument();
        doc.Characters.Add(new EditorItem { Id = "hero", Name = "주인공" });
        doc.Enemies.Add(new EditorItem { Id = "enemy", Name = "적" });
        doc.Stages.Add(new EditorItem { Id = "stage", Name = "첫 스테이지", X = 24, Y = 48, Spawns = [new SpawnPoint { ActorId = "Player", X = 24, Y = 48 }] });
        Validate(doc);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(doc, JsonOptions);
        var roundTrip = JsonSerializer.Deserialize<OverrideDocument>(bytes, JsonOptions)!;
        if (roundTrip.SchemaVersion != 1 || roundTrip.Characters[0].Name != "주인공" || roundTrip.Stages[0].Spawns[0].X != 24)
            throw new InvalidOperationException("UTF-8 JSON round-trip mismatch.");
        roundTrip.Characters[0].Id = roundTrip.Enemies[0].Id;
        bool duplicateRejected = false;
        try { Validate(roundTrip); } catch (InvalidDataException) { duplicateRejected = true; }
        if (!duplicateRejected) throw new InvalidOperationException("Duplicate IDs were accepted.");
        roundTrip.Characters[0].Id = "hero";
        roundTrip.Characters[0].MaxHealth = 0;
        bool rangeRejected = false;
        try { Validate(roundTrip); } catch (InvalidDataException) { rangeRejected = true; }
        if (!rangeRejected) throw new InvalidOperationException("Out-of-range health was accepted.");
        var contract = JsonDocument.Parse(JsonSerializer.Serialize(doc, JsonOptions)).RootElement;
        if (!contract.TryGetProperty("characters", out _) || !contract.GetProperty("characters")[0].TryGetProperty("max_health", out _) || contract.GetProperty("characters")[0].TryGetProperty("health", out _))
            throw new InvalidOperationException("Serialized model does not match runtime schema v1 field names.");
        AnimationWorkspaceForm.ContractSelfTest();
        EditorForm.PlaytestPreparationSelfTest();
    }

    internal static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    internal static void Validate(OverrideDocument doc)
    {
        if (doc.SchemaVersion != 1) throw new InvalidDataException("schema_version은 1이어야 합니다.");
        if (doc.Characters is null || doc.Enemies is null || doc.Stages is null) throw new InvalidDataException("characters, enemies, stages 배열이 모두 필요합니다.");
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (kind, items) in new[] { ("캐릭터", doc.Characters), ("적", doc.Enemies), ("스테이지", doc.Stages) })
        foreach (var item in items)
        {
            if (item is null) throw new InvalidDataException($"{kind} 목록에 빈 항목이 있습니다.");
            if (string.IsNullOrWhiteSpace(item.Id)) throw new InvalidDataException($"{kind} ID는 비워둘 수 없습니다.");
            if (!ids.Add(item.Id.Trim())) throw new InvalidDataException($"중복 ID: {item.Id}");
            Check(item.MaxHealth, 1, 999, item.Id, "체력"); Check(item.AttackDamage, 0, 999, item.Id, "공격력");
            Check(item.WalkSpeed, 1, 2000, item.Id, "속도"); Check(item.AttackHitStun, 0, 10, item.Id, "경직");
            Check(item.AttackKnockback, 0, 3000, item.Id, "넉백"); Check(item.AttackRange, 1, 1200, item.Id, "공격 범위");
            Check(item.RecoveryDuration, 0, 30, item.Id, "쿨다운/회복"); Check(item.WindupDuration, 0, 10, item.Id, "선딜"); Check(item.ActiveDuration, 0, 10, item.Id, "활성시간");
            if (item.SkillCooldowns is null || item.SkillCooldowns.Length != 2) throw new InvalidDataException($"{item.Id}: 스킬 쿨다운은 두 값이 필요합니다.");
            foreach (var cooldown in item.SkillCooldowns) Check(cooldown, 0, 60, item.Id, "스킬 쿨다운");
            Check(item.X, -100000, 100000, item.Id, "배치 X"); Check(item.Y, -100000, 100000, item.Id, "배치 Y");
            Check(item.Left, -100000, 100000, item.Id, "경계 왼쪽"); Check(item.Top, -100000, 100000, item.Id, "경계 위쪽");
            Check(item.Right, -100000, 100000, item.Id, "경계 오른쪽"); Check(item.Bottom, -100000, 100000, item.Id, "경계 아래쪽");
            if (item.Right <= item.Left || item.Bottom <= item.Top) throw new InvalidDataException($"{item.Id}: 경계의 오른쪽/아래쪽은 왼쪽/위쪽보다 커야 합니다.");
            if (item.Ai is null) throw new InvalidDataException($"{item.Id}: AI 값은 객체여야 합니다.");
            foreach (var (key, value) in item.Ai) Check(value, key == "notice_range" ? 1 : 0, key == "notice_range" ? 3000 : key == "attack_depth_tolerance" ? 500 : key == "separation_radius" ? 1000 : 2000, item.Id, $"AI {key}");
            if (item.PlayerBounds is null || item.Spawns is null) throw new InvalidDataException($"{item.Id}: player_bounds/spawns 형식이 잘못되었습니다.");
            foreach (var point in item.Spawns) { if (point is null || string.IsNullOrWhiteSpace(point.ActorId)) throw new InvalidDataException($"{item.Id}: 배치 actor_id가 비어 있습니다."); Check(point.X, -100000, 100000, item.Id, "배치 X"); Check(point.Y, -100000, 100000, item.Id, "배치 Y"); }
        }
    }
    private static void Check(double v, double min, double max, string id, string field)
    { if (double.IsNaN(v) || double.IsInfinity(v) || v < min || v > max) throw new InvalidDataException($"{id}: {field} 값은 {min}~{max} 범위여야 합니다."); }
    private static void Check(int v, int min, int max, string id, string field)
    { if (v < min || v > max) throw new InvalidDataException($"{id}: {field} 값은 {min}~{max} 범위여야 합니다."); }
}

internal sealed class EditorForm : Form
{
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    private readonly ComboBox category = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
    private readonly ListBox items = new() { Dock = DockStyle.Fill };
    private readonly Panel fields = new() { Dock = DockStyle.Fill, AutoScroll = true };
    private readonly Dictionary<string, Control> editors = new();
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(5) };
    private readonly TextBox godotPathBox = new() { Width = 310 };
    private readonly TextBox projectRootBox = new() { Width = 310 };
    private OverrideDocument document = new();
    private EditorItem? selected;
    private string currentPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "data", "editor", "overrides.json"));
    private bool loading;
    private bool documentDirty;
    private readonly HashSet<string> invalidFields = new(StringComparer.Ordinal);
    private readonly string? acceptanceDir;
    private readonly bool runtimeRoundtrip;
    private readonly bool playtestAcceptance;
    private readonly Dictionary<string, Button> playtestButtons = new(StringComparer.Ordinal);
    private string? acceptanceGodot;
    private string? acceptanceProjectRoot;
    private int playtestAcceptanceStep;
    private DateTime playtestStepStarted;
    private System.Windows.Forms.Timer? acceptanceTimer;
    private int acceptanceStep;
    private Process? playtestProcess;
    private string? playtestWorkspace;
    private int? lastPlaytestExitCode;
    private string? lastPlaytestWorkspace;
    private readonly StringBuilder playtestOutput = new();
    internal int ExitCode { get; private set; }

    public EditorForm(string? acceptanceDir = null, bool runtimeRoundtrip = false, bool playtestAcceptance = false, string? playtestGodot = null, string? playtestProjectRoot = null)
    {
        this.acceptanceDir = acceptanceDir;
        this.runtimeRoundtrip = runtimeRoundtrip;
        this.playtestAcceptance = playtestAcceptance;
        acceptanceGodot = playtestGodot;
        acceptanceProjectRoot = playtestProjectRoot;
        Text = "BeltScroll 에디터"; Width = 1120; Height = 780; MinimumSize = new Size(900, 600); StartPosition = FormStartPosition.CenterScreen;
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 3, Padding = new Padding(8) };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290)); root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 72)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1 };
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 36)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        category.Items.AddRange(["캐릭터", "적", "스테이지"]); category.SelectedIndex = 0; left.Controls.Add(category, 0, 0); left.Controls.Add(items, 0, 1);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        foreach (var (label, action) in new (string label, Action action)[] { ("새 항목", AddItem), ("복제", CloneItem), ("삭제", DeleteItem) })
        { var b = new Button { Text = label, AutoSize = true }; b.Click += (_, _) => action(); actions.Controls.Add(b); }
        left.Controls.Add(actions, 0, 2); root.Controls.Add(left, 0, 0); root.Controls.Add(fields, 1, 0);
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 }; footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        footer.Controls.Add(status, 0, 0); var fileButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
        foreach (var (label, action) in new (string label, Action action)[] { ("아트·애니메이션 작업공간", OpenAnimationWorkspace), ("저장", Save), ("불러오기", LoadFile), ("다른 이름으로 저장", SaveAs) })
        { var b = new Button { Text = label, AutoSize = true }; b.Click += (_, _) => action(); fileButtons.Controls.Add(b); }
        footer.Controls.Add(fileButtons, 1, 0); root.Controls.Add(footer, 0, 2); root.SetColumnSpan(footer, 2);
        var playtestBar = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = true, AutoScroll = true, Padding = new Padding(2) };
        projectRootBox.Text = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, ".."));
        playtestBar.Controls.Add(new Label { Text = "Godot 실행 파일", AutoSize = true, Padding = new Padding(2, 7, 0, 0) }); playtestBar.Controls.Add(godotPathBox);
        var chooseGodot = new Button { Text = "찾기…", AutoSize = true }; chooseGodot.Click += (_, _) => ChooseGodot(); playtestBar.Controls.Add(chooseGodot);
        playtestBar.Controls.Add(new Label { Text = "프로젝트 루트", AutoSize = true, Padding = new Padding(2, 7, 0, 0) }); playtestBar.Controls.Add(projectRootBox);
        var chooseProject = new Button { Text = "찾기…", AutoSize = true }; chooseProject.Click += (_, _) => ChooseProject(); playtestBar.Controls.Add(chooseProject);
        foreach (var (label, scene) in new[] { ("게임 전투 테스트", "res://scenes/game/main.tscn"), ("전투 연습장 실행", "res://scenes/review/m6i_combat_test_arena.tscn") })
        { var b = new Button { Text = label, AutoSize = true }; b.Click += (_, _) => LaunchPlaytest(scene); playtestButtons[scene] = b; playtestBar.Controls.Add(b); }
        root.Controls.Add(playtestBar, 0, 1); root.SetColumnSpan(playtestBar, 2); Controls.Add(root);
        category.SelectedIndexChanged += (_, _) => RefreshList(); items.SelectedIndexChanged += (_, _) => SelectItem();
        BuildFields(); RefreshList();
        FormClosed += (_, _) => CleanupPlaytestOnEditorClose();
        if (acceptanceDir is not null)
        {
            Directory.CreateDirectory(acceptanceDir);
            currentPath = Path.Combine(acceptanceDir, "overrides.json");
            string fixture = Path.Combine(acceptanceDir, "source-overrides.json");
            if (!File.Exists(fixture)) File.WriteAllText(fixture, """{"schema_version":1,"characters":[{"id":"Player","max_health":5,"walk_speed":280,"custom_runtime_key":{"korean":"보존"}}],"enemies":[{"id":"ForestRaider","name":"숲 레이더","max_health":10}],"stages":[{"id":"AcceptanceStage","name":"인수 스테이지","left":10,"top":20,"right":1000,"bottom":900,"spawns":[{"actor_id":"Player","x":960,"y":780,"custom_spawn_field":"preserve"}],"custom_stage_field":{"enabled":true}}],"custom_document_field":"preserve"}""", new UTF8Encoding(false));
            LoadPath(fixture);
            currentPath = Path.Combine(acceptanceDir, "overrides.json");
            if (playtestAcceptance)
            {
                if (string.IsNullOrWhiteSpace(acceptanceGodot) || string.IsNullOrWhiteSpace(acceptanceProjectRoot)) throw new InvalidDataException("Playtest acceptance requires --godot and --project-root.");
                godotPathBox.Text = acceptanceGodot;
                projectRootBox.Text = acceptanceProjectRoot;
            }
            acceptanceTimer = new System.Windows.Forms.Timer { Interval = 180 };
            acceptanceTimer.Tick += (_, _) => RunAcceptanceStep();
            Shown += (_, _) => acceptanceTimer.Start();
        }
        else LoadStartupFile();
        if (acceptanceDir is not null) status.Text = $"인수 시험: {acceptanceDir}";
    }

    private IEnumerable<EditorItem> CurrentList => category.SelectedIndex switch { 0 => document.Characters, 1 => document.Enemies, _ => document.Stages };
    private string CurrentKind => category.SelectedIndex switch { 0 => "캐릭터", 1 => "적", _ => "스테이지" };
    private void BuildFields()
    {
        var grid = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, Padding = new Padding(12) };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180)); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var names = new (string key, string label, bool multiline)[] { ("Id", "ID", false), ("Name", "이름", false), ("MaxHealth", "체력", false), ("AttackDamage", "공격력", false), ("WalkSpeed", "속도", false), ("AttackHitStun", "경직", false), ("AttackKnockback", "넉백", false), ("AttackRange", "공격 범위", false), ("RecoveryDuration", "쿨다운/회복 (초)", false), ("WindupDuration", "선딜 (초)", false), ("ActiveDuration", "활성시간 (초)", false), ("X", "플레이어 배치 X", false), ("Y", "플레이어 배치 Y", false), ("Left", "경계 왼쪽", false), ("Top", "경계 위쪽", false), ("Right", "경계 오른쪽", false), ("Bottom", "경계 아래쪽", false), ("SkillCooldowns", "스킬 쿨다운 JSON 배열", false), ("Ai", "AI JSON 객체", false), ("PlayerBounds", "플레이어 경계 JSON 객체", false), ("Spawns", "배치 JSON 배열", false) };
        foreach (var (key, label, _) in names)
        {
            int row = grid.RowCount++; grid.RowStyles.Add(new RowStyle(SizeType.Absolute, 38)); grid.Controls.Add(new Label { Text = label, TextAlign = ContentAlignment.MiddleLeft, Dock = DockStyle.Fill }, 0, row);
            var box = new TextBox { Dock = DockStyle.Fill, Tag = key }; box.TextChanged += (_, _) => FieldChanged(box); editors[key] = box; grid.Controls.Add(box, 1, row);
        }
        fields.Controls.Add(grid);
    }
    private void RefreshList()
    {
        loading = true; items.Items.Clear(); foreach (var item in CurrentList) items.Items.Add(item); loading = false;
        selected = null; SetFields(null);
    }
    private void SelectItem() { if (loading) return; selected = items.SelectedItem as EditorItem; SetFields(selected); }
    private void SetFields(EditorItem? item)
    {
        loading = true; invalidFields.Clear(); foreach (var (key, control) in editors) { var value = item?.GetType().GetProperty(key)?.GetValue(item); control.Text = value is string text ? text : value is null ? "" : value is Array or System.Collections.IDictionary or System.Collections.IList ? JsonSerializer.Serialize(value, Program.JsonOptions) : Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? ""; control.Enabled = item != null; control.BackColor = SystemColors.Window; } loading = false;
    }
    private void FieldChanged(TextBox box)
    {
        if (loading || selected is null) return;
        string key = (string)box.Tag!; var prop = typeof(EditorItem).GetProperty(key)!; object? value;
        if (prop.PropertyType == typeof(string)) value = box.Text;
        else if (prop.PropertyType == typeof(int)) value = int.TryParse(box.Text, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var i) ? i : null;
        else if (prop.PropertyType == typeof(double)) value = double.TryParse(box.Text, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null;
        else { try { value = JsonSerializer.Deserialize(box.Text, prop.PropertyType, Program.JsonOptions); } catch (JsonException) { value = null; } }
        if (value is null) { invalidFields.Add(key); box.BackColor = Color.MistyRose; status.Text = $"{key}: 입력값이 올바르지 않습니다. 전투 테스트는 저장된 설정을 사용합니다."; return; }
        invalidFields.Remove(key); prop.SetValue(selected, value); box.BackColor = SystemColors.Window; documentDirty = true; status.Text = "수정됨 — 전투 테스트는 저장된 설정을 사용합니다."; int ix = items.SelectedIndex; if (ix >= 0) { items.Items[ix] = selected; items.SelectedIndex = ix; }
    }
    private void AddItem()
    {
        string prefix = category.SelectedIndex == 0 ? "character" : category.SelectedIndex == 1 ? "enemy" : "stage";
        var item = new EditorItem { Id = UniqueId($"{prefix}_{DateTime.Now:yyyyMMdd_HHmmssfff}"), Name = $"새 {CurrentKind}" };
        if (category.SelectedIndex == 0) document.Characters.Add(item); else if (category.SelectedIndex == 1) document.Enemies.Add(item); else document.Stages.Add(item);
        documentDirty = true; status.Text = "수정됨 — 전투 테스트는 저장된 설정을 사용합니다."; RefreshList(); items.SelectedItem = item;
    }
    private void CloneItem()
    {
        if (selected is null) return; var clone = selected.Copy(); clone.Id = UniqueId($"{clone.Id}_copy"); clone.Name = $"{clone.Name} 복사본";
        if (category.SelectedIndex == 0) document.Characters.Add(clone); else if (category.SelectedIndex == 1) document.Enemies.Add(clone); else document.Stages.Add(clone);
        documentDirty = true; status.Text = "수정됨 — 전투 테스트는 저장된 설정을 사용합니다."; RefreshList(); items.SelectedItem = clone;
    }
    private string UniqueId(string candidate)
    {
        var used = document.Characters.Concat(document.Enemies).Concat(document.Stages)
            .Select(item => item.Id).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!used.Contains(candidate)) return candidate;
        for (int suffix = 2; ; suffix++)
        {
            string unique = $"{candidate}_{suffix}";
            if (!used.Contains(unique)) return unique;
        }
    }
    private void DeleteItem()
    {
        if (selected is null || (acceptanceDir is null && MessageBox.Show($"'{selected.Name}' 항목을 삭제할까요?", "삭제 확인", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)) return;
        if (category.SelectedIndex == 0) document.Characters.Remove(selected); else if (category.SelectedIndex == 1) document.Enemies.Remove(selected); else document.Stages.Remove(selected); documentDirty = true; status.Text = "수정됨 — 전투 테스트는 저장된 설정을 사용합니다."; RefreshList();
    }
    private void LoadFile()
    {
        using var dialog = new OpenFileDialog { Title = "오버라이드 불러오기", Filter = "JSON 파일 (*.json)|*.json|모든 파일 (*.*)|*.*", FileName = Path.GetFileName(currentPath) };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { LoadPath(dialog.FileName); currentPath = dialog.FileName; status.Text = $"불러옴: {currentPath}"; }
        catch (Exception ex) { ShowError("불러오기 실패", ex); }
    }
    private void LoadStartupFile()
    {
        if (!File.Exists(currentPath)) { status.Text = $"새 문서: {currentPath}"; return; }
        try { LoadPath(currentPath); status.Text = $"불러옴: {currentPath}"; }
        catch (Exception ex) { status.Text = $"기존 파일을 적용하지 않았습니다: {ex.Message}"; }
    }

    private void OpenAnimationWorkspace()
    {
        using var workspace = new AnimationWorkspaceForm();
        workspace.ShowDialog(this);
    }

    private void ChooseGodot()
    {
        using var dialog = new OpenFileDialog { Title = "Godot 실행 파일 선택", Filter = "Godot 실행 파일 (godot*.exe)|godot*.exe|실행 파일 (*.exe)|*.exe" };
        if (dialog.ShowDialog(this) == DialogResult.OK) godotPathBox.Text = Path.GetFullPath(dialog.FileName);
    }

    private void ChooseProject()
    {
        using var dialog = new FolderBrowserDialog { Description = "project.godot 파일이 있는 프로젝트 폴더를 선택하세요.", SelectedPath = Directory.Exists(projectRootBox.Text) ? projectRootBox.Text : AppContext.BaseDirectory };
        if (dialog.ShowDialog(this) == DialogResult.OK) projectRootBox.Text = Path.GetFullPath(dialog.SelectedPath);
    }

    private void LaunchPlaytest(string scene)
    {
        string? workspaceForLaunch = null;
        Process? processForLaunch = null;
        bool processStarted = false;
        try
        {
            if (playtestProcess is { HasExited: false }) throw new InvalidOperationException("이미 전투 테스트 프로세스가 실행 중입니다.");
            if (playtestProcess is not null) { playtestProcess.Dispose(); playtestProcess = null; }
            string root = ValidateProjectRoot(projectRootBox.Text);
            string godot = ValidateGodotExecutable(godotPathBox.Text);
            string sourceOverrides = Path.GetFullPath(currentPath);
            if (!File.Exists(sourceOverrides)) throw new FileNotFoundException("현재 설정을 먼저 저장하세요.", sourceOverrides);
            var saved = JsonSerializer.Deserialize<OverrideDocument>(File.ReadAllText(sourceOverrides, Encoding.UTF8), Program.JsonOptions) ?? throw new InvalidDataException("저장된 전투 설정이 비어 있습니다.");
            Program.Validate(saved);
            workspaceForLaunch = CreatePlaytestWorkspace(root, sourceOverrides);
            playtestWorkspace = workspaceForLaunch;
            lastPlaytestExitCode = null;
            lastPlaytestWorkspace = workspaceForLaunch;
            playtestOutput.Clear();
            var start = new ProcessStartInfo { FileName = godot, WorkingDirectory = workspaceForLaunch, UseShellExecute = false, CreateNoWindow = false, RedirectStandardOutput = true, RedirectStandardError = true };
            start.ArgumentList.Add("--path"); start.ArgumentList.Add(workspaceForLaunch); start.ArgumentList.Add("--scene"); start.ArgumentList.Add(scene);
            processForLaunch = new Process { StartInfo = start, EnableRaisingEvents = true };
            playtestProcess = processForLaunch;
            processForLaunch.OutputDataReceived += (_, e) => AppendPlaytestOutput(e.Data);
            processForLaunch.ErrorDataReceived += (_, e) => AppendPlaytestOutput(e.Data);
            processForLaunch.Exited += (_, _) =>
            {
                try { BeginInvoke((Action)(() => PlaytestExited())); } catch (ObjectDisposedException) { } catch (InvalidOperationException) { }
            };
            processStarted = processForLaunch.Start();
            if (!processStarted) throw new InvalidOperationException("Godot 프로세스를 시작하지 못했습니다.");
            processForLaunch.BeginOutputReadLine(); processForLaunch.BeginErrorReadLine();
            processForLaunch.Refresh();
            if (processForLaunch.HasExited) throw new InvalidOperationException($"Godot가 창을 표시하기 전에 종료되었습니다 (코드 {processForLaunch.ExitCode}).");
            status.Text = $"실행 중: {scene} · 적용: 저장된 설정 {sourceOverrides}" + (documentDirty || invalidFields.Count > 0 ? " · 미저장 편집값은 적용되지 않음" : "") + $" · 임시 프로젝트 {playtestWorkspace}";
        }
        catch (Exception ex)
        {
            bool exitedBeforeLaunchCompleted = !processStarted;
            if (processStarted) { try { exitedBeforeLaunchCompleted = processForLaunch!.HasExited; } catch { exitedBeforeLaunchCompleted = true; } }
            if (exitedBeforeLaunchCompleted)
            {
                if (ReferenceEquals(playtestProcess, processForLaunch)) playtestProcess = null;
                processForLaunch?.Dispose();
                if (workspaceForLaunch is not null)
                {
                    try { if (Directory.Exists(workspaceForLaunch)) Directory.Delete(workspaceForLaunch, true); } catch { }
                    if (playtestWorkspace == workspaceForLaunch) playtestWorkspace = null;
                }
            }
            ShowError("전투 테스트 실행 실패", ex);
        }
    }

    private void AppendPlaytestOutput(string? line)
    {
        if (string.IsNullOrEmpty(line)) return;
        lock (playtestOutput) { if (playtestOutput.Length < 20000) playtestOutput.AppendLine(line); }
    }

    private void PlaytestExited()
    {
        if (playtestProcess is null) return;
        int code; try { code = playtestProcess.ExitCode; } catch (InvalidOperationException) { return; }
        string output; lock (playtestOutput) output = playtestOutput.ToString();
        lastPlaytestExitCode = code;
        lastPlaytestWorkspace = playtestWorkspace;
        status.Text = $"전투 테스트 종료 코드: {code}";
        if (code != 0 && acceptanceDir is null) MessageBox.Show(this, $"Godot가 종료 코드 {code}(으)로 종료되었습니다.\n\n{output}", "전투 테스트 오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
        playtestProcess.Dispose(); playtestProcess = null;
        if (playtestWorkspace is not null) { try { Directory.Delete(playtestWorkspace, true); } catch (Exception ex) { status.Text += $" · 임시 파일 정리 실패: {ex.Message}"; } playtestWorkspace = null; }
    }

    private void CleanupPlaytestOnEditorClose()
    {
        if (playtestProcess is { } process)
        {
            try { if (!process.HasExited) { process.Kill(true); process.WaitForExit(5000); } } catch { }
            try { process.Dispose(); } catch { }
            playtestProcess = null;
        }
        if (playtestWorkspace is not null)
        {
            try { if (Directory.Exists(playtestWorkspace)) Directory.Delete(playtestWorkspace, true); }
            catch (Exception ex) { if (acceptanceDir is not null) File.WriteAllText(Path.Combine(acceptanceDir, "playtest-cleanup-error.txt"), ex.ToString(), new UTF8Encoding(false)); }
            playtestWorkspace = null;
        }
    }

    internal static string ValidateGodotExecutable(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new InvalidDataException("Godot 실행 파일 경로를 지정하세요.");
        string full = Path.GetFullPath(path);
        if (!File.Exists(full) || !Path.GetExtension(full).Equals(".exe", StringComparison.OrdinalIgnoreCase) || !Path.GetFileName(full).StartsWith("godot", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("실행 파일은 존재하는 godot*.exe여야 합니다.");
        return full;
    }

    internal static string ValidateProjectRoot(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new InvalidDataException("Godot 프로젝트 폴더를 지정하세요.");
        string full = Path.GetFullPath(path);
        if (!Directory.Exists(full) || !File.Exists(Path.Combine(full, "project.godot")) || !File.Exists(Path.Combine(full, "scenes/game/main.tscn")) || !File.Exists(Path.Combine(full, "scenes/review/m6i_combat_test_arena.tscn")))
            throw new InvalidDataException("project.godot와 게임/전투 연습장 씬이 있는 BeltScroll 프로젝트 폴더를 선택하세요.");
        return full;
    }

    private static string CreatePlaytestWorkspace(string sourceRoot, string savedOverrides)
    {
        string workspace = Path.Combine(Path.GetTempPath(), "BeltScrollCombatPlaytest_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(workspace);
        try
        {
            var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", ".godot", ".projecthub", ".qa_logs", "dist", "temp", "bin", "obj", "tests", "docs", "editor" };
            foreach (string entry in Directory.EnumerateFileSystemEntries(sourceRoot))
            {
                string name = Path.GetFileName(entry);
                if ((File.GetAttributes(entry) & FileAttributes.ReparsePoint) != 0) continue;
                if (Directory.Exists(entry)) { if (!excluded.Contains(name)) CopyDirectory(entry, Path.Combine(workspace, name), excluded); }
                else File.Copy(entry, Path.Combine(workspace, name), true);
            }
            string overrideTarget = Path.Combine(workspace, "data", "editor", "overrides.json");
            Directory.CreateDirectory(Path.GetDirectoryName(overrideTarget)!);
            File.Copy(savedOverrides, overrideTarget, true);
            return workspace;
        }
        catch { try { Directory.Delete(workspace, true); } catch { } throw; }
    }

    private static void CopyDirectory(string source, string destination, HashSet<string> excluded)
    {
        Directory.CreateDirectory(destination);
        foreach (string file in Directory.EnumerateFiles(source))
        {
            if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) continue;
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), true);
        }
        foreach (string child in Directory.EnumerateDirectories(source))
            if (!excluded.Contains(Path.GetFileName(child)) && (File.GetAttributes(child) & FileAttributes.ReparsePoint) == 0) CopyDirectory(child, Path.Combine(destination, Path.GetFileName(child)), excluded);
    }

    internal static void PlaytestPreparationSelfTest()
    {
        string root = Path.Combine(Path.GetTempPath(), "BeltScrollPlaytestSelfTest_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string workspace = "";
        try
        {
            Directory.CreateDirectory(Path.Combine(root, "data", "editor"));
            Directory.CreateDirectory(Path.Combine(root, "scenes", "game"));
            Directory.CreateDirectory(Path.Combine(root, "scenes", "review"));
            File.WriteAllText(Path.Combine(root, "project.godot"), "config/name=\"fixture\"", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(root, "scenes", "game", "main.tscn"), "game", new UTF8Encoding(false));
            File.WriteAllText(Path.Combine(root, "scenes", "review", "m6i_combat_test_arena.tscn"), "practice", new UTF8Encoding(false));
            string original = "{\"schema_version\":1,\"characters\":[],\"enemies\":[],\"stages\":[]}";
            string overrides = Path.Combine(root, "data", "editor", "overrides.json");
            File.WriteAllText(overrides, original, new UTF8Encoding(false));
            Directory.CreateDirectory(Path.Combine(root, ".git"));
            File.WriteAllText(Path.Combine(root, ".git", "must-not-copy"), "excluded");
            if (ValidateProjectRoot(root) != Path.GetFullPath(root)) throw new InvalidOperationException("Project root validation failed.");
            workspace = CreatePlaytestWorkspace(root, overrides);
            string staged = Path.Combine(workspace, "data", "editor", "overrides.json");
            if (File.ReadAllText(staged, Encoding.UTF8) != original || File.ReadAllText(overrides, Encoding.UTF8) != original || File.Exists(Path.Combine(workspace, ".git", "must-not-copy")))
                throw new InvalidOperationException("Playtest workspace did not isolate the saved settings from the source project.");
            bool rejected = false;
            try { ValidateProjectRoot(Path.GetTempPath()); } catch (InvalidDataException) { rejected = true; }
            if (!rejected) throw new InvalidOperationException("An invalid project root was accepted.");
        }
        finally
        {
            if (workspace.Length > 0 && Directory.Exists(workspace)) Directory.Delete(workspace, true);
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
    private void LoadPath(string path)
    {
        var loaded = JsonSerializer.Deserialize<OverrideDocument>(File.ReadAllText(path, Encoding.UTF8), Program.JsonOptions) ?? throw new InvalidDataException("JSON 문서가 비어 있습니다.");
        Program.Validate(loaded);
        foreach (var stage in loaded.Stages) { var spawn = stage.Spawns.FirstOrDefault(s => s.ActorId == "Player"); if (spawn is not null) { stage.X = spawn.X; stage.Y = spawn.Y; } }
        document = loaded; documentDirty = false; RefreshList();
    }
    private void Save() => SaveTo(currentPath);
    private void SaveAs()
    {
        using var dialog = new SaveFileDialog { Title = "오버라이드 저장", Filter = "JSON 파일 (*.json)|*.json", FileName = Path.GetFileName(currentPath), DefaultExt = "json" };
        if (dialog.ShowDialog(this) == DialogResult.OK) SaveAsTo(dialog.FileName);
    }
    private bool SaveAsTo(string path)
    {
        if (!SaveTo(path)) return false;
        currentPath = Path.GetFullPath(path);
        return true;
    }
    private bool SaveTo(string path)
    {
        try
        {
            if (invalidFields.Count > 0) throw new InvalidDataException("입력 오류가 있는 편집값을 고친 뒤 저장하세요.");
            var output = JsonSerializer.Deserialize<OverrideDocument>(JsonSerializer.Serialize(document, Program.JsonOptions), Program.JsonOptions)!;
            for (int i = 0; i < output.Stages.Count; i++)
            {
                // X/Y are editor-only properties and are intentionally ignored by JSON serialization.
                // Restore them from the live model before writing the runtime Player spawn.
                output.Stages[i].X = document.Stages[i].X;
                output.Stages[i].Y = document.Stages[i].Y;
                var playerSpawn = output.Stages[i].Spawns.FirstOrDefault(s => s.ActorId == "Player");
                if (playerSpawn is null) output.Stages[i].Spawns.Add(new SpawnPoint { ActorId = "Player", X = output.Stages[i].X, Y = output.Stages[i].Y });
                else { playerSpawn.X = output.Stages[i].X; playerSpawn.Y = output.Stages[i].Y; }
            }
            Program.Validate(output); string full = Path.GetFullPath(path); Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            byte[] content = new UTF8Encoding(false).GetBytes(JsonSerializer.Serialize(output, Program.JsonOptions) + Environment.NewLine);
            string temp = full + ".tmp." + Guid.NewGuid().ToString("N");
            try
            {
                using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(content); stream.Flush(true); }
                if (File.Exists(full)) { string backup = full + ".bak"; File.Copy(full, backup, true); File.Move(temp, full, true); }
                else File.Move(temp, full);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
            documentDirty = false; status.Text = $"저장 완료: {full}";
            return true;
        }
        catch (Exception ex) { ShowError("저장 실패", ex); return false; }
    }
    private void ShowError(string title, Exception ex) { status.Text = $"오류: {ex.Message}"; if (acceptanceDir is null) MessageBox.Show(this, ex.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Error); }

    private void RunAcceptanceStep()
    {
        try
        {
            if (playtestAcceptance) { RunPlaytestAcceptanceStep(); return; }
            if (runtimeRoundtrip) { RunRuntimeRoundtripAcceptance(); return; }
            acceptanceStep++;
            switch (acceptanceStep)
            {
                case 1: category.SelectedIndex = 0; items.SelectedIndex = 0; if (items.Items.Count != 1 || selected is null || selected.Name is not null) throw new Exception("Partial record did not load with missing name."); break;
                case 2: ((Button)FindButton("새 항목")).PerformClick(); if (selected is null || document.Characters.Count != 2) throw new Exception("Character create failed."); break;
                case 3: ((Button)FindButton("복제")).PerformClick(); var idBox = (TextBox)editors["Id"]; idBox.Text = "acceptance_character_clone"; var health = (TextBox)editors["MaxHealth"]; health.Text = "7"; if (selected?.Id != "acceptance_character_clone" || selected.MaxHealth != 7) throw new Exception("Character clone/edit failed."); ((Button)FindButton("삭제")).PerformClick(); if (document.Characters.Any(x => x.Id == "acceptance_character_clone")) throw new Exception("Character clone delete failed."); items.SelectedItem = document.Characters.Single(x => x.Id.StartsWith("character_", StringComparison.Ordinal)); ((Button)FindButton("삭제")).PerformClick(); if (document.Characters.Count != 1) throw new Exception("Created character delete failed."); break;
                case 4: category.SelectedIndex = 1; items.SelectedItem = document.Enemies.Single(); ((Button)FindButton("복제")).PerformClick(); ((TextBox)editors["Id"]).Text = "acceptance_enemy_clone"; ((TextBox)editors["MaxHealth"]).Text = "17"; if (selected?.Id != "acceptance_enemy_clone" || selected.MaxHealth != 17) throw new Exception("Enemy clone/edit failed."); ((Button)FindButton("삭제")).PerformClick(); if (document.Enemies.Count != 1) throw new Exception("Enemy clone delete failed."); ((Button)FindButton("새 항목")).PerformClick(); if (document.Enemies.Count != 2) throw new Exception("Enemy create failed."); ((Button)FindButton("삭제")).PerformClick(); if (document.Enemies.Count != 1) throw new Exception("Created enemy delete failed."); break;
                case 5: category.SelectedIndex = 2; var stage = document.Stages.Single(x => x.Id == "AcceptanceStage"); items.SelectedItem = stage; if (stage.X != 960 || stage.Y != 780) throw new Exception("Stage Player placement did not load."); ((Button)FindButton("복제")).PerformClick(); ((TextBox)editors["Id"]).Text = "acceptance_stage_clone"; ((TextBox)editors["X"]).Text = "961"; ((TextBox)editors["Y"]).Text = "781"; if (selected?.Id != "acceptance_stage_clone" || selected.X != 961 || selected.Y != 781) throw new Exception("Stage clone/edit failed."); if (!SaveTo(currentPath)) throw new Exception("Stage save failed."); ((Button)FindButton("삭제")).PerformClick(); if (document.Stages.Any(x => x.Id == "acceptance_stage_clone")) throw new Exception("Stage clone delete failed."); ((Button)FindButton("새 항목")).PerformClick(); if (document.Stages.Count != 2) throw new Exception("Stage create failed."); ((Button)FindButton("삭제")).PerformClick(); if (document.Stages.Count != 1) throw new Exception("Created stage delete failed."); break;
                case 6: category.SelectedIndex = 0; var player = document.Characters.Single(x => x.Id == "Player"); items.SelectedItem = player; if (!SaveTo(currentPath)) throw new Exception("Could not establish the preexisting save fixture."); string priorPath = currentPath; byte[] priorContent = File.ReadAllBytes(currentPath); string priorBackupPath = currentPath + ".bak"; bool hadPriorBackup = File.Exists(priorBackupPath); byte[] priorBackup = hadPriorBackup ? File.ReadAllBytes(priorBackupPath) : []; ((TextBox)editors["MaxHealth"]).Text = "0"; string rejectedPath = Path.Combine(acceptanceDir!, "failed-save", "should-not-exist.json"); if (SaveAsTo(rejectedPath) || currentPath != priorPath || File.Exists(rejectedPath)) throw new Exception("Failed Save As changed the active path or created a file."); bool backupChanged = File.Exists(priorBackupPath) != hadPriorBackup || (hadPriorBackup && !File.ReadAllBytes(priorBackupPath).SequenceEqual(priorBackup)); if (SaveTo(currentPath) || !status.Text.StartsWith("오류:") || !File.ReadAllBytes(currentPath).SequenceEqual(priorContent) || backupChanged) throw new Exception("Rejected overwrite changed the prior file or backup."); ((TextBox)editors["MaxHealth"]).Text = "6"; if (!SaveTo(currentPath)) throw new Exception("Corrected value did not save."); break;
                case 7: File.WriteAllText(Path.Combine(acceptanceDir!, "malformed.json"), "{invalid", new UTF8Encoding(false)); var before = document; try { LoadPath(Path.Combine(acceptanceDir!, "malformed.json")); throw new Exception("Malformed JSON was accepted."); } catch (JsonException) { if (!ReferenceEquals(before, document)) throw new Exception("Malformed load replaced the current document."); } break;
                case 8: if (!SaveTo(currentPath)) throw new Exception("Save failed."); if (!File.Exists(currentPath + ".bak")) throw new Exception("Backup was not created on overwrite."); LoadPath(currentPath); if (document.Characters.Single(x => x.Id == "Player").MaxHealth != 6) throw new Exception("Saved value did not survive reopen."); var root = JsonDocument.Parse(File.ReadAllText(currentPath, Encoding.UTF8)).RootElement; var playerJson = root.GetProperty("characters")[0]; var savedStage = root.GetProperty("stages")[0]; var savedSpawn = savedStage.GetProperty("spawns").EnumerateArray().Single(x => x.GetProperty("actor_id").GetString() == "Player"); if (playerJson.TryGetProperty("name", out _) || !playerJson.TryGetProperty("custom_runtime_key", out _)) throw new Exception("Partial name or unknown character field was not preserved."); if (savedSpawn.GetProperty("x").GetDouble() != 960 || savedSpawn.GetProperty("y").GetDouble() != 780 || !savedStage.TryGetProperty("custom_stage_field", out _) || !savedSpawn.TryGetProperty("custom_spawn_field", out _) || !root.TryGetProperty("custom_document_field", out _)) throw new Exception("Stage placement or unknown source fields were not preserved."); break;
                case 9: CaptureAcceptance(); WriteAcceptanceReport(true, "WinForms message loop verified character, enemy, and stage create/clone/edit/delete; range rejection; malformed JSON rejection; save/reopen/backup; source field and stage placement preservation; normal close."); acceptanceTimer!.Stop(); ExitCode = 0; Close(); break;
            }
        }
        catch (Exception ex) { acceptanceTimer?.Stop(); ExitCode = 1; if (playtestAcceptance) WritePlaytestAcceptanceReport(false, ex.ToString()); else WriteAcceptanceReport(false, ex.ToString()); try { CaptureAcceptance(); } catch { } Close(); }
    }

    private void RunPlaytestAcceptanceStep()
    {
        var gameScene = "res://scenes/game/main.tscn";
        var arenaScene = "res://scenes/review/m6i_combat_test_arena.tscn";
        switch (playtestAcceptanceStep)
        {
            case 0:
                category.SelectedIndex = 0;
                var player = document.Characters.Single(x => x.Id == "Player");
                SelectForEdit("characters", player);
                ((TextBox)editors["MaxHealth"]).Text = "11";
                category.SelectedIndex = 1;
                var raider = document.Enemies.Single(x => x.Id == "ForestRaider");
                SelectForEdit("enemies", raider);
                ((TextBox)editors["MaxHealth"]).Text = "23";
                if (!SaveTo(currentPath)) throw new InvalidOperationException("Saved Player/ForestRaider fixture could not be written.");
                category.SelectedIndex = 0; SelectForEdit("characters", player);
                ((TextBox)editors["MaxHealth"]).Text = "77";
                if (!documentDirty) throw new InvalidOperationException("Unsaved edit marker was not set.");
                playtestStepStarted = DateTime.UtcNow;
                playtestButtons[gameScene].PerformClick();
                if (!status.Text.Contains("미저장 편집값은 적용되지 않음", StringComparison.Ordinal) || !status.Text.Contains(currentPath, StringComparison.Ordinal)) throw new InvalidOperationException("Launch status did not distinguish the saved settings path from unsaved edits.");
                playtestAcceptanceStep = 1;
                break;
            case 1:
                if (playtestProcess is null) throw new InvalidOperationException("Godot exited before a process window could be inspected.");
                playtestProcess.Refresh();
                if (playtestProcess.HasExited) throw new InvalidOperationException($"Godot exited before its window appeared (code {playtestProcess.ExitCode}).");
                if (DateTime.UtcNow - playtestStepStarted > TimeSpan.FromSeconds(30)) throw new TimeoutException("Godot process window did not become available within 30 seconds.");
                if (playtestProcess.MainWindowHandle == IntPtr.Zero || !IsWindowVisible(playtestProcess.MainWindowHandle)) return;
                VerifyStagedCombatValues(playtestWorkspace!);
                VerifyPlaytestRuntimeValues(playtestWorkspace!, gameScene);
                if (!playtestProcess.CloseMainWindow()) throw new InvalidOperationException("Godot window did not accept a close request.");
                playtestStepStarted = DateTime.UtcNow;
                playtestAcceptanceStep = 2;
                break;
            case 2:
                if (playtestProcess is not null)
                {
                    if (DateTime.UtcNow - playtestStepStarted > TimeSpan.FromSeconds(15)) throw new TimeoutException("Godot did not exit after its window was closed.");
                    return;
                }
                if (lastPlaytestExitCode != 0) throw new InvalidOperationException($"Game playtest exited abnormally (code {lastPlaytestExitCode?.ToString() ?? "unknown"}).");
                if (playtestWorkspace is not null || (lastPlaytestWorkspace is not null && Directory.Exists(lastPlaytestWorkspace))) throw new IOException("Game playtest temporary project was not removed after exit.");
                playtestButtons[arenaScene].PerformClick();
                playtestStepStarted = DateTime.UtcNow;
                playtestAcceptanceStep = 3;
                break;
            case 3:
                if (playtestProcess is null) throw new InvalidOperationException("Godot exited before the arena window could be inspected.");
                playtestProcess.Refresh();
                if (playtestProcess.HasExited) throw new InvalidOperationException($"Godot exited before the arena window appeared (code {playtestProcess.ExitCode}).");
                if (DateTime.UtcNow - playtestStepStarted > TimeSpan.FromSeconds(30)) throw new TimeoutException("Combat arena window did not become available within 30 seconds.");
                if (playtestProcess.MainWindowHandle == IntPtr.Zero || !IsWindowVisible(playtestProcess.MainWindowHandle)) return;
                VerifyStagedCombatValues(playtestWorkspace!);
                VerifyPlaytestRuntimeValues(playtestWorkspace!, arenaScene);
                if (!playtestProcess.CloseMainWindow()) throw new InvalidOperationException("Combat arena window did not accept a close request.");
                playtestStepStarted = DateTime.UtcNow;
                playtestAcceptanceStep = 4;
                break;
            case 4:
                if (playtestProcess is not null)
                {
                    if (DateTime.UtcNow - playtestStepStarted > TimeSpan.FromSeconds(15)) throw new TimeoutException("Godot did not exit after its window was closed.");
                    return;
                }
                if (lastPlaytestExitCode != 0) throw new InvalidOperationException($"Combat arena exited abnormally (code {lastPlaytestExitCode?.ToString() ?? "unknown"}).");
                if (playtestWorkspace is not null || (lastPlaytestWorkspace is not null && Directory.Exists(lastPlaytestWorkspace))) throw new IOException("Temporary playtest project was not cleaned up after exit.");
                CaptureAcceptance();
                WritePlaytestAcceptanceReport(true, "Both WinForms launch buttons started visible Godot windows. Headless probes confirmed the saved Player and ForestRaider health values on live scene instances for both scenes; each GUI process exited with code 0 and the unsaved Player edit remained unapplied.");
                acceptanceTimer!.Stop(); ExitCode = 0; Close();
                break;
        }
    }

    private static void VerifyStagedCombatValues(string workspace)
    {
        string path = Path.Combine(workspace, "data", "editor", "overrides.json");
        var staged = JsonSerializer.Deserialize<OverrideDocument>(File.ReadAllText(path, Encoding.UTF8), Program.JsonOptions) ?? throw new InvalidDataException("Staged overrides are empty.");
        Program.Validate(staged);
        if (staged.Characters.Single(x => x.Id == "Player").MaxHealth != 11 || staged.Enemies.Single(x => x.Id == "ForestRaider").MaxHealth != 23)
            throw new InvalidDataException("The isolated project does not contain the saved Player/ForestRaider values.");
    }

    private void VerifyPlaytestRuntimeValues(string workspace, string scene)
    {
        string probe = Path.Combine(acceptanceProjectRoot!, "tests", "m6j_editor_runtime_apply_probe.gd");
        if (!File.Exists(probe)) throw new FileNotFoundException("Runtime actor verification probe is missing.", probe);
        var start = new ProcessStartInfo { FileName = acceptanceGodot!, WorkingDirectory = workspace, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add("--headless");
        start.ArgumentList.Add("--path"); start.ArgumentList.Add(workspace);
        start.ArgumentList.Add("--script"); start.ArgumentList.Add(probe);
        start.ArgumentList.Add("--"); start.ArgumentList.Add(scene); start.ArgumentList.Add("11"); start.ArgumentList.Add("23");
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Godot runtime actor verification process did not start.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(30000))
        {
            try { process.Kill(true); process.WaitForExit(5000); } catch { }
            throw new TimeoutException("Godot runtime actor verification timed out after 30 seconds.");
        }
        string stdout = stdoutTask.GetAwaiter().GetResult();
        string stderr = stderrTask.GetAwaiter().GetResult();
        string probeName = scene.Contains("m6i_combat_test_arena", StringComparison.Ordinal) ? "arena" : "game";
        File.WriteAllText(Path.Combine(acceptanceDir!, probeName + "-runtime-probe.stdout.txt"), stdout, new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(acceptanceDir!, probeName + "-runtime-probe.stderr.txt"), stderr, new UTF8Encoding(false));
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"Saved combat values did not reach the live actors for {scene} (exit {process.ExitCode}).\n{stdout}\n{stderr}");
    }

    private void WritePlaytestAcceptanceReport(bool passed, string details)
    {
        var report = new { product = "BeltScrollEditor", mode = "--playtest-gui-acceptance", verificationClass = "automated_gui", passed, details, actualOsMouseInput = false, humanInputReview = "not_performed", buttonResults = new[] { new { button = "게임 전투 테스트", scene = "res://scenes/game/main.tscn" }, new { button = "전투 연습장 실행", scene = "res://scenes/review/m6i_combat_test_arena.tscn" } }, savedValues = new { PlayerMaxHealth = 11, ForestRaiderMaxHealth = 23 }, runtimeActorValuesVerified = passed, unsavedPlayerMaxHealth = 77, processExitCode = lastPlaytestExitCode, temporaryWorkspaceCleaned = playtestWorkspace is null && (lastPlaytestWorkspace is null || !Directory.Exists(lastPlaytestWorkspace)), workingDirectory = Environment.CurrentDirectory, screenshot = Path.Combine(acceptanceDir!, "gui-capture.png"), exitCode = passed ? 0 : 1 };
        File.WriteAllText(Path.Combine(acceptanceDir!, "playtest-gui-acceptance.json"), JsonSerializer.Serialize(report, Program.JsonOptions), new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(acceptanceDir!, "exit-code.txt"), (passed ? "0" : "1") + Environment.NewLine, new UTF8Encoding(false));
    }
    private void RunRuntimeRoundtripAcceptance()
    {
        try
        {
            acceptanceTimer?.Stop();
            SetNumeric("characters", "Player", "MaxHealth", "9");
            SetNumeric("characters", "Player", "WalkSpeed", "301");
            SetNumeric("characters", "Player", "AttackDamage", "13");
            SetNumeric("enemies", "ForestRaider", "MaxHealth", "6");
            SetNumeric("enemies", "ForestRaider", "WalkSpeed", "131");
            SetNumeric("enemies", "ForestRaider", "AttackDamage", "4");
            var raider = document.Enemies.Single(x => x.Id == "ForestRaider");
            var ai = new Dictionary<string, double>(raider.Ai) { ["notice_range"] = 610, ["attack_depth_tolerance"] = 42, ["separation_radius"] = 126, ["separation_strength"] = 147 };
            SelectForEdit("enemies", raider);
            ((TextBox)editors["Ai"]).Text = JsonSerializer.Serialize(ai, Program.JsonOptions);
            if (selected?.Ai["notice_range"] != 610) throw new Exception("ForestRaider AI edit failed.");
            var stage = document.Stages.Single(x => x.Id == "ForestRuins");
            SelectForEdit("stages", stage);
            stage.X = 946; stage.Y = 792;
            var playerSpawn = stage.Spawns.Single(x => x.ActorId == "Player"); playerSpawn.X = 946; playerSpawn.Y = 792;
            var raiderSpawn = stage.Spawns.Single(x => x.ActorId == "ForestRaider"); raiderSpawn.X = 710; raiderSpawn.Y = 772;
            SetFields(stage);
            if (!SaveTo(currentPath)) throw new Exception("Runtime roundtrip output did not save.");
            LoadPath(currentPath);
            var savedPlayer = document.Characters.Single(x => x.Id == "Player");
            var savedRaider = document.Enemies.Single(x => x.Id == "ForestRaider");
            var savedStage = document.Stages.Single(x => x.Id == "ForestRuins");
            if (savedPlayer.MaxHealth != 9 || savedPlayer.WalkSpeed != 301 || savedPlayer.AttackDamage != 13 || savedRaider.MaxHealth != 6 || savedRaider.WalkSpeed != 131 || savedRaider.AttackDamage != 4 || savedRaider.Ai["notice_range"] != 610 || savedStage.Spawns.Single(x => x.ActorId == "Player").X != 946 || savedStage.Spawns.Single(x => x.ActorId == "ForestRaider").Y != 772)
                throw new Exception("Saved real runtime records did not survive reopen.");
            CaptureAcceptance();
            WriteAcceptanceReport(true, "Actual Player, ForestRaider, and ForestRuins records edited through the visible WinForms GUI controls, saved, reopened, and checked. OS mouse input was not used; the acceptance driver invoked real form controls through WinForms on the GUI message loop.", new[] { "Player.max_health=9", "Player.walk_speed=301", "Player.attack_damage=13", "ForestRaider.max_health=6", "ForestRaider.walk_speed=131", "ForestRaider.attack_damage=4", "ForestRaider.ai.notice_range=610", "ForestRaider.ai.attack_depth_tolerance=42", "ForestRaider.ai.separation_radius=126", "ForestRaider.ai.separation_strength=147", "ForestRuins.Player spawn=(946,792)", "ForestRuins.ForestRaider spawn=(710,772)" });
            ExitCode = 0; Close();
        }
        catch (Exception ex) { ExitCode = 1; WriteAcceptanceReport(false, ex.ToString(), Array.Empty<string>()); try { CaptureAcceptance(); } catch { } Close(); }
    }
    private void SetNumeric(string kind, string id, string field, string value)
    {
        var list = kind == "characters" ? document.Characters : document.Enemies;
        var item = list.Single(x => x.Id == id);
        SelectForEdit(kind, item);
        ((TextBox)editors[field]).Text = value;
        if (selected != item) throw new Exception($"Could not select {id} for GUI edit.");
    }
    private void SelectForEdit(string kind, EditorItem item)
    {
        category.SelectedIndex = kind == "characters" ? 0 : kind == "enemies" ? 1 : 2;
        items.SelectedItem = item;
        if (selected != item) throw new Exception($"Could not select {item.Id} in GUI list.");
    }
    private Control FindButton(string label) => Controls.Find(label, true).FirstOrDefault() ?? FindControls(this).OfType<Button>().First(b => b.Text == label);
    private static IEnumerable<Control> FindControls(Control root) { foreach (Control child in root.Controls) { yield return child; foreach (var descendant in FindControls(child)) yield return descendant; } }
    private void CaptureAcceptance() { using var bitmap = new Bitmap(Math.Max(1, Width), Math.Max(1, Height)); DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size)); bitmap.Save(Path.Combine(acceptanceDir!, "gui-capture.png"), System.Drawing.Imaging.ImageFormat.Png); }
    private void WriteAcceptanceReport(bool passed, string details, string[]? editedValues = null)
    {
        var report = new { product = "BeltScrollEditor", mode = runtimeRoundtrip ? "--gui-acceptance --runtime-roundtrip" : "--gui-acceptance", passed, details, editedValues = editedValues ?? Array.Empty<string>(), actualOsMouseInput = false, uiAutomation = "WinForms controls invoked on the visible GUI message loop", steps = runtimeRoundtrip ? new[] { "actual Player/ForestRaider/ForestRuins loaded", "stats, AI and placement edited in GUI fields", "save", "reopen", "saved actual records verified", "capture", "normal close" } : new[] { "startup partial record load", "character create/clone/edit/delete", "enemy create/clone/edit/delete", "stage create/clone/edit/delete", "stage Player coordinate preservation", "range rejection", "failed Save As path preservation", "failed overwrite preserves existing file and backup", "malformed JSON rejection", "save", "reopen", "backup", "unknown document/item/spawn field preservation", "normal close" }, workingDirectory = Environment.CurrentDirectory, output = currentPath, screenshot = Path.Combine(acceptanceDir!, "gui-capture.png"), exitCode = passed ? 0 : 1 };
        File.WriteAllText(Path.Combine(acceptanceDir!, "gui-acceptance.json"), JsonSerializer.Serialize(report, Program.JsonOptions), new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(acceptanceDir!, "exit-code.txt"), (passed ? "0" : "1") + Environment.NewLine, new UTF8Encoding(false));
    }
}
