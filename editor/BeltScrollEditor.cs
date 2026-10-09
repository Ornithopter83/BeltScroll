using System.ComponentModel;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Forms;

namespace BeltScrollEditor;

public sealed class OverrideDocument
{
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 1;
    [JsonPropertyName("characters")] public List<EditorItem> Characters { get; set; } = [];
    [JsonPropertyName("enemies")] public List<EditorItem> Enemies { get; set; } = [];
    [JsonPropertyName("stages")] public List<EditorItem> Stages { get; set; } = [];
}

public sealed class EditorItem
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
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
}

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Any(a => a.Equals("--self-test", StringComparison.OrdinalIgnoreCase)))
        {
            try { SelfTest(); Console.WriteLine("BeltScrollEditor self-test passed."); return 0; }
            catch (Exception e) { Console.Error.WriteLine($"Self-test failed: {e.Message}"); return 1; }
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new EditorForm());
        return 0;
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
            if (string.IsNullOrWhiteSpace(item.Name)) throw new InvalidDataException($"{item.Id}: 이름은 비워둘 수 없습니다.");
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
    private readonly ComboBox category = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
    private readonly ListBox items = new() { Dock = DockStyle.Fill };
    private readonly Panel fields = new() { Dock = DockStyle.Fill, AutoScroll = true };
    private readonly Dictionary<string, Control> editors = new();
    private readonly Label status = new() { AutoSize = true, Padding = new Padding(5) };
    private OverrideDocument document = new();
    private EditorItem? selected;
    private string currentPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "data", "editor", "overrides.json"));
    private bool loading;

    public EditorForm()
    {
        Text = "BeltScroll 에디터"; Width = 1120; Height = 780; MinimumSize = new Size(900, 600); StartPosition = FormStartPosition.CenterScreen;
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2, Padding = new Padding(8) };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 290)); root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); root.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        var left = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1 };
        left.RowStyles.Add(new RowStyle(SizeType.Absolute, 36)); left.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); left.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        category.Items.AddRange(["캐릭터", "적", "스테이지"]); category.SelectedIndex = 0; left.Controls.Add(category, 0, 0); left.Controls.Add(items, 0, 1);
        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false };
        foreach (var (label, action) in new (string label, Action action)[] { ("새 항목", AddItem), ("복제", CloneItem), ("삭제", DeleteItem) })
        { var b = new Button { Text = label, AutoSize = true }; b.Click += (_, _) => action(); actions.Controls.Add(b); }
        left.Controls.Add(actions, 0, 2); root.Controls.Add(left, 0, 0); root.Controls.Add(fields, 1, 0);
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 }; footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        footer.Controls.Add(status, 0, 0); var fileButtons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, WrapContents = false };
        foreach (var (label, action) in new (string label, Action action)[] { ("저장", Save), ("불러오기", LoadFile), ("다른 이름으로 저장", SaveAs) })
        { var b = new Button { Text = label, AutoSize = true }; b.Click += (_, _) => action(); fileButtons.Controls.Add(b); }
        footer.Controls.Add(fileButtons, 1, 0); root.Controls.Add(footer, 0, 1); root.SetColumnSpan(footer, 2); Controls.Add(root);
        category.SelectedIndexChanged += (_, _) => RefreshList(); items.SelectedIndexChanged += (_, _) => SelectItem();
        BuildFields(); RefreshList(); status.Text = $"파일: {currentPath}";
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
        loading = true; foreach (var (key, control) in editors) { var value = item?.GetType().GetProperty(key)?.GetValue(item); control.Text = value is string text ? text : value is null ? "" : value is Array or System.Collections.IDictionary or System.Collections.IList ? JsonSerializer.Serialize(value, Program.JsonOptions) : Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture) ?? ""; control.Enabled = item != null; } loading = false;
    }
    private void FieldChanged(TextBox box)
    {
        if (loading || selected is null) return;
        string key = (string)box.Tag!; var prop = typeof(EditorItem).GetProperty(key)!; object? value;
        if (prop.PropertyType == typeof(string)) value = box.Text;
        else if (prop.PropertyType == typeof(int)) value = int.TryParse(box.Text, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var i) ? i : null;
        else if (prop.PropertyType == typeof(double)) value = double.TryParse(box.Text, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null;
        else { try { value = JsonSerializer.Deserialize(box.Text, prop.PropertyType, Program.JsonOptions); } catch (JsonException) { value = null; } }
        if (value is null) { box.BackColor = Color.MistyRose; status.Text = $"{key}: 숫자 형식이 올바르지 않습니다."; return; }
        prop.SetValue(selected, value); box.BackColor = SystemColors.Window; int ix = items.SelectedIndex; if (ix >= 0) { items.Items[ix] = selected; items.SelectedIndex = ix; }
    }
    private void AddItem()
    {
        var item = new EditorItem { Id = $"{(category.SelectedIndex == 0 ? "character" : category.SelectedIndex == 1 ? "enemy" : "stage")}_{DateTime.Now:yyyyMMdd_HHmmssfff}", Name = $"새 {CurrentKind}" };
        if (category.SelectedIndex == 0) document.Characters.Add(item); else if (category.SelectedIndex == 1) document.Enemies.Add(item); else document.Stages.Add(item);
        RefreshList(); items.SelectedItem = item;
    }
    private void CloneItem()
    {
        if (selected is null) return; var clone = selected.Copy(); clone.Id += "_copy"; clone.Name += " 복사본";
        if (category.SelectedIndex == 0) document.Characters.Add(clone); else if (category.SelectedIndex == 1) document.Enemies.Add(clone); else document.Stages.Add(clone);
        RefreshList(); items.SelectedItem = clone;
    }
    private void DeleteItem()
    {
        if (selected is null || MessageBox.Show($"'{selected.Name}' 항목을 삭제할까요?", "삭제 확인", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        if (category.SelectedIndex == 0) document.Characters.Remove(selected); else if (category.SelectedIndex == 1) document.Enemies.Remove(selected); else document.Stages.Remove(selected); RefreshList();
    }
    private void LoadFile()
    {
        using var dialog = new OpenFileDialog { Title = "오버라이드 불러오기", Filter = "JSON 파일 (*.json)|*.json|모든 파일 (*.*)|*.*", FileName = Path.GetFileName(currentPath) };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { var loaded = JsonSerializer.Deserialize<OverrideDocument>(File.ReadAllText(dialog.FileName, Encoding.UTF8), Program.JsonOptions) ?? throw new InvalidDataException("JSON 문서가 비어 있습니다."); Program.Validate(loaded); foreach (var stage in loaded.Stages) { var playerSpawn = stage.Spawns.FirstOrDefault(s => s.ActorId == "Player"); if (playerSpawn is not null) { stage.X = playerSpawn.X; stage.Y = playerSpawn.Y; } } document = loaded; currentPath = dialog.FileName; RefreshList(); status.Text = $"불러옴: {currentPath}"; }
        catch (Exception ex) { ShowError("불러오기 실패", ex); }
    }
    private void Save() => SaveTo(currentPath);
    private void SaveAs()
    {
        using var dialog = new SaveFileDialog { Title = "오버라이드 저장", Filter = "JSON 파일 (*.json)|*.json", FileName = Path.GetFileName(currentPath), DefaultExt = "json" };
        if (dialog.ShowDialog(this) == DialogResult.OK) { currentPath = dialog.FileName; SaveTo(currentPath); }
    }
    private void SaveTo(string path)
    {
        try
        {
            var output = JsonSerializer.Deserialize<OverrideDocument>(JsonSerializer.Serialize(document, Program.JsonOptions), Program.JsonOptions)!;
            foreach (var stage in output.Stages) { var playerSpawn = stage.Spawns.FirstOrDefault(s => s.ActorId == "Player"); if (playerSpawn is null) stage.Spawns.Add(new SpawnPoint { ActorId = "Player", X = stage.X, Y = stage.Y }); else { playerSpawn.X = stage.X; playerSpawn.Y = stage.Y; } }
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
            status.Text = $"저장 완료: {full}";
        }
        catch (Exception ex) { ShowError("저장 실패", ex); }
    }
    private void ShowError(string title, Exception ex) { status.Text = $"오류: {ex.Message}"; MessageBox.Show(this, ex.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Error); }
}
