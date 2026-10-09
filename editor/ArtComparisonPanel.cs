using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace BeltScrollEditor;

/// <summary>Compares the selected frame with a second source at the game's 3x pixel scale.</summary>
internal sealed class ArtComparisonPanel : UserControl
{
    private readonly ComparisonCanvas canvas = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(48, 52, 60) };
    private readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 112 };
    private readonly TrackBar opacity = new() { Minimum = 0, Maximum = 100, Value = 50, TickFrequency = 25, Width = 120 };
    private readonly CheckBox mirror = new() { Text = "좌우 미러", AutoSize = true };
    private readonly Label sourceLabel = new() { AutoSize = true, Padding = new Padding(4, 7, 4, 0) };
    private string? currentPath;
    private string? comparisonPath;

    public ArtComparisonPanel()
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, Padding = new Padding(4) };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, AutoScroll = true };
        toolbar.Controls.Add(new Label { Text = "비교 모드", AutoSize = true, Padding = new Padding(2, 7, 0, 0) });
        mode.Items.AddRange(["나란히", "겹쳐 보기"]); mode.SelectedIndex = 0; toolbar.Controls.Add(mode);
        var open = new Button { Text = "비교 원화 열기", AutoSize = true }; open.Click += (_, _) => SelectComparison(); toolbar.Controls.Add(open);
        toolbar.Controls.Add(new Label { Text = "겹침 불투명도", AutoSize = true, Padding = new Padding(5, 7, 0, 0) }); toolbar.Controls.Add(opacity); toolbar.Controls.Add(mirror);
        toolbar.Controls.Add(sourceLabel); layout.Controls.Add(toolbar, 0, 0); layout.Controls.Add(canvas, 0, 1); Controls.Add(layout);
        mode.SelectedIndexChanged += (_, _) => UpdateCanvas(); opacity.ValueChanged += (_, _) => UpdateCanvas(); mirror.CheckedChanged += (_, _) => UpdateCanvas();
    }

    public void SetCurrentImage(string? path)
    {
        currentPath = path; sourceLabel.Text = string.IsNullOrWhiteSpace(path) ? "현재 프레임 없음" : Path.GetFileName(path);
        UpdateCanvas();
    }

    internal void ConfigureForAcceptance(string comparisonImagePath)
    {
        comparisonPath = comparisonImagePath;
        mode.SelectedIndex = 0; opacity.Value = 50; mirror.Checked = false;
        mode.SelectedIndex = 1; opacity.Value = 72; mirror.Checked = true;
        UpdateCanvas();
        if (!canvas.HasBothImages) throw new InvalidOperationException("The comparison canvas did not load both artwork sources.");
    }

    private void SelectComparison()
    {
        using var dialog = new OpenFileDialog { Title = "비교할 두 번째 원화 선택", Filter = "이미지 파일|*.png;*.bmp;*.gif;*.jpg;*.jpeg" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        comparisonPath = dialog.FileName; UpdateCanvas();
    }

    private void UpdateCanvas() => canvas.Configure(currentPath, comparisonPath, mode.SelectedIndex == 1, opacity.Value / 100f, mirror.Checked);
}

internal sealed class ComparisonCanvas : Control
{
    private Image? current;
    private Image? comparison;
    private bool overlay;
    private float alpha = .5f;
    private bool mirror;
    internal bool HasBothImages => current is not null && comparison is not null;
    public ComparisonCanvas() { DoubleBuffered = true; ResizeRedraw = true; }
    public void Configure(string? currentPath, string? comparisonPath, bool overlayMode, float overlayAlpha, bool mirrored)
    {
        current?.Dispose(); comparison?.Dispose(); current = Load(currentPath); comparison = Load(comparisonPath);
        overlay = overlayMode; alpha = overlayAlpha; mirror = mirrored; Invalidate();
    }
    private static Image? Load(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
        using var stream = File.OpenRead(path); using var decoded = Image.FromStream(stream); return new Bitmap(decoded);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e); var g = e.Graphics; g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
        const int cell = 16;
        using var a = new SolidBrush(Color.FromArgb(54, 58, 66)); using var b = new SolidBrush(Color.FromArgb(70, 74, 82));
        for (int y = 0; y < Height; y += cell) for (int x = 0; x < Width; x += cell) g.FillRectangle(((x / cell + y / cell) & 1) == 0 ? a : b, x, y, cell, cell);
        if (current is null && comparison is null) { TextRenderer.DrawText(g, "현재 프레임을 선택하고 비교 원화를 여세요", Font, ClientRectangle, Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter); return; }
        int gameScale = 3;
        if (overlay)
        {
            Image? basis = current ?? comparison!; int w = basis.Width * gameScale, h = basis.Height * gameScale;
            float x = (Width - w) / 2f, y = (Height - h) / 2f;
            DrawImage(g, basis, x, y, w, h, mirror, 1f);
            Image? top = comparison is null ? null : current is null ? comparison : comparison;
            if (top is not null && (current is null || !ReferenceEquals(top, current))) DrawImage(g, top, x, y, w, h, mirror, alpha);
        }
        else
        {
            DrawSide(g, current, Width / 4f, gameScale, mirror, "현재 프레임"); DrawSide(g, comparison, Width * 3f / 4f, gameScale, mirror, "비교 원화");
        }
        using var pen = new Pen(Color.FromArgb(190, Color.Gold), 1); g.DrawLine(pen, 0, Height - 2, Width, Height - 2);
    }
    private void DrawSide(Graphics g, Image? image, float centerX, int scale, bool flip, string label)
    {
        TextRenderer.DrawText(g, label + " · 3×", Font, new Point((int)(centerX - 70), 8), Color.White);
        if (image is null) return;
        int w = image.Width * scale, h = image.Height * scale; DrawImage(g, image, centerX - w / 2f, (Height - h) / 2f, w, h, flip, 1f);
    }
    private static void DrawImage(Graphics g, Image image, float x, float y, int width, int height, bool flip, float alpha)
    {
        var state = g.Save(); if (flip) { g.TranslateTransform(x * 2 + width, 0); g.ScaleTransform(-1, 1); }
        using var attributes = new System.Drawing.Imaging.ImageAttributes();
        var matrix = new System.Drawing.Imaging.ColorMatrix { Matrix33 = alpha }; attributes.SetColorMatrix(matrix, System.Drawing.Imaging.ColorMatrixFlag.Default, System.Drawing.Imaging.ColorAdjustType.Bitmap);
        g.DrawImage(image, new Rectangle((int)x, (int)y, width, height), 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attributes); g.Restore(state);
    }
    protected override void Dispose(bool disposing) { if (disposing) { current?.Dispose(); comparison?.Dispose(); } base.Dispose(disposing); }
}
