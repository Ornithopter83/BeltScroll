using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace BeltScrollEditor;

/// <summary>Compares source artwork in a 576px review space with independent pixel zoom and pan.</summary>
internal sealed class ArtComparisonPanel : UserControl
{
    private readonly ComparisonCanvas canvas = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(48, 52, 60) };
    private readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 112 };
    private readonly TrackBar opacity = new() { Minimum = 0, Maximum = 100, Value = 50, TickFrequency = 25, Width = 100 };
    private readonly TrackBar zoom = new() { Minimum = 100, Maximum = 400, Value = 100, TickFrequency = 100, Width = 112 };
    private readonly CheckBox mirror = new() { Text = "좌우 미러", AutoSize = true };
    private readonly Label zoomLabel = new() { AutoSize = true, Padding = new Padding(0, 7, 2, 0) };
    private readonly Label sourceLabel = new() { AutoSize = true, Padding = new Padding(4, 7, 4, 0) };
    private string? currentPath;
    private string? comparisonPath;
    private FootAnchor currentAnchor = new();
    private double frameDuration;

    public ArtComparisonPanel()
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 2, ColumnCount = 1, Padding = new Padding(4) };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40)); layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, WrapContents = false, AutoScroll = true };
        toolbar.Controls.Add(new Label { Text = "비교 모드", AutoSize = true, Padding = new Padding(2, 7, 0, 0) });
        mode.Items.AddRange(["나란히", "겹쳐 보기"]); mode.SelectedIndex = 0; toolbar.Controls.Add(mode);
        var open = new Button { Text = "비교 원화 열기", AutoSize = true }; open.Click += (_, _) => SelectComparison(); toolbar.Controls.Add(open);
        toolbar.Controls.Add(new Label { Text = "겹침", AutoSize = true, Padding = new Padding(5, 7, 0, 0) }); toolbar.Controls.Add(opacity); toolbar.Controls.Add(mirror);
        toolbar.Controls.Add(new Label { Text = "픽셀 줌", AutoSize = true, Padding = new Padding(5, 7, 0, 0) }); toolbar.Controls.Add(zoom); toolbar.Controls.Add(zoomLabel);
        toolbar.Controls.Add(sourceLabel); layout.Controls.Add(toolbar, 0, 0); layout.Controls.Add(canvas, 0, 1); Controls.Add(layout);
        mode.SelectedIndexChanged += (_, _) => UpdateCanvas(); opacity.ValueChanged += (_, _) => UpdateCanvas(); mirror.CheckedChanged += (_, _) => UpdateCanvas();
        zoom.ValueChanged += (_, _) => { canvas.Zoom = zoom.Value / 100f; zoomLabel.Text = $"{zoom.Value}%"; canvas.Invalidate(); };
        zoomLabel.Text = "100%";
    }

    public void SetCurrentFrame(string? path, FootAnchor? anchor, double duration, string? frameDescription = null)
    {
        currentPath = path;
        currentAnchor = anchor is null ? new FootAnchor() : new FootAnchor { X = anchor.X, Y = anchor.Y };
        frameDuration = duration;
        sourceLabel.Text = string.IsNullOrWhiteSpace(frameDescription) ? "현재 프레임 없음" : frameDescription;
        UpdateCanvas();
    }

    internal void ConfigureForAcceptance(string comparisonImagePath)
    {
        comparisonPath = comparisonImagePath;
        mode.SelectedIndex = 0; opacity.Value = 50; mirror.Checked = false; zoom.Value = 100;
        mode.SelectedIndex = 1; opacity.Value = 72; mirror.Checked = true;
        UpdateCanvas();
        if (!canvas.HasBothImages) throw new InvalidOperationException("The comparison canvas did not load both artwork sources.");
    }

    internal string[] ExerciseAcceptance(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        if (!canvas.HasBothImages || frameDuration <= 0) throw new InvalidOperationException("A timed current frame and comparison artwork are required.");
        zoom.Value = 100;
        mode.SelectedIndex = 0; canvas.Invalidate(); CaptureCanvas(Path.Combine(outputDirectory, "comparison-side-by-side.png"));
        if (canvas.CurrentReviewHeight > 576.1f || canvas.CurrentTop < 0 || canvas.CurrentBottom > canvas.Height) throw new InvalidOperationException("The default 576px review view clipped the full character.");
        mode.SelectedIndex = 1; canvas.Invalidate(); CaptureCanvas(Path.Combine(outputDirectory, "comparison-overlay.png"));
        zoom.Value = 200; canvas.Invalidate(); CaptureCanvas(Path.Combine(outputDirectory, "comparison-zoom.png"));
        if (canvas.CurrentReviewHeight <= 576) throw new InvalidOperationException("Independent pixel zoom did not enlarge the source artwork.");
        Point beforePan = canvas.PanOffset; canvas.SimulateDrag(new Point(14, -8)); CaptureCanvas(Path.Combine(outputDirectory, "comparison-pan.png"));
        if (canvas.PanOffset == beforePan) throw new InvalidOperationException("Dragging did not pan the zoomed artwork.");
        zoom.Value = 100; canvas.Invalidate();
        return ["576px default review size", "side-by-side full-body and foot anchor", "overlay full-body and foot anchor", "independent 200% pixel zoom", "drag pan at pixel zoom", "source dimensions and display multiplier", "actual frame duration"];
    }

    private void CaptureCanvas(string path)
    {
        using var bitmap = new Bitmap(Math.Max(1, canvas.Width), Math.Max(1, canvas.Height));
        canvas.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size)); bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private void SelectComparison()
    {
        using var dialog = new OpenFileDialog { Title = "비교할 두 번째 원화 선택", Filter = "이미지 파일|*.png;*.bmp;*.gif;*.jpg;*.jpeg" };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        comparisonPath = dialog.FileName; UpdateCanvas();
    }

    private void UpdateCanvas() => canvas.Configure(currentPath, comparisonPath, mode.SelectedIndex == 1, opacity.Value / 100f, mirror.Checked, currentAnchor, frameDuration);
}

internal sealed class ComparisonCanvas : Control
{
    private readonly record struct RenderBox(RectangleF Bounds, float Scale, float AnchorY)
    {
        public float Height => Bounds.Height;
        public float Top => Bounds.Top;
        public float Bottom => Bounds.Bottom;
    }
    private Image? current;
    private Image? comparison;
    private string? currentPath;
    private string? comparisonPath;
    private bool overlay;
    private float alpha = .5f;
    private bool mirror;
    private FootAnchor anchor = new();
    private double frameDuration;
    private Point pan;
    private Point dragOrigin;
    private Point panOrigin;
    private bool dragging;
    internal bool HasBothImages => current is not null && comparison is not null;
    internal float Zoom { get; set; } = 1f;
    internal Point PanOffset => pan;
    internal float CurrentReviewHeight => current is null ? 0 : GetBox(current, 0, overlay ? Width : Width / 2, Height).Height;
    internal float CurrentTop => current is null ? 0 : GetBox(current, 0, overlay ? Width : Width / 2, Height).Top;
    internal float CurrentBottom => current is null ? 0 : GetBox(current, 0, overlay ? Width : Width / 2, Height).Bottom;
    public ComparisonCanvas() { DoubleBuffered = true; ResizeRedraw = true; Cursor = Cursors.Hand; }
    public void Configure(string? currentPath, string? comparisonPath, bool overlayMode, float overlayAlpha, bool mirrored, FootAnchor footAnchor, double duration)
    {
        if (!string.Equals(this.currentPath, currentPath, StringComparison.OrdinalIgnoreCase)) { current?.Dispose(); current = Load(currentPath); this.currentPath = currentPath; }
        if (!string.Equals(this.comparisonPath, comparisonPath, StringComparison.OrdinalIgnoreCase)) { comparison?.Dispose(); comparison = Load(comparisonPath); this.comparisonPath = comparisonPath; }
        overlay = overlayMode; alpha = overlayAlpha; mirror = mirrored;
        anchor = new FootAnchor { X = footAnchor.X, Y = footAnchor.Y }; frameDuration = duration; Invalidate();
    }
    private Image? Load(string? path)
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
        if (overlay)
        {
            Image? basis = current ?? comparison!;
            var box = GetBox(basis, 0, Width, Height);
            DrawAnchorLine(g, box.AnchorY, 0, Width);
            DrawImage(g, basis, box, mirror, 1f); DrawAnchor(g, box, anchor, mirror, "발 anchor");
            if (comparison is not null && current is not null) { var top = GetBox(comparison, 0, Width, Height); DrawImage(g, comparison, top, mirror, alpha); DrawAnchor(g, top, anchor, mirror, ""); }
            DrawHud(g, 0, Width, current, "겹쳐 보기", frameDuration);
        }
        else
        {
            int half = Width / 2;
            DrawSide(g, current, 0, half, "현재 프레임", frameDuration);
            DrawSide(g, comparison, half, Width - half, "비교 원화", frameDuration);
        }
        using var pen = new Pen(Color.FromArgb(190, Color.Gold), 1); g.DrawLine(pen, 0, Height - 2, Width, Height - 2);
    }
    private void DrawSide(Graphics g, Image? image, int left, int width, string label, double duration)
    {
        DrawHud(g, left, width, image, label, duration);
        if (image is null) return;
        var box = GetBox(image, left, width, Height); DrawAnchorLine(g, box.AnchorY, left, width); DrawImage(g, image, box, mirror, 1f); DrawAnchor(g, box, anchor, mirror, "발 anchor");
    }
    private void DrawHud(Graphics g, int left, int width, Image? image, string label, double duration)
    {
        string time = label == "현재 프레임" && duration > 0 ? $" · {duration:0.###}s" : "";
        string dimensions = image is null ? "" : $" · {image.Width}×{image.Height}";
        string scale = image is null ? "" : $" · 표시 {GetBox(image, left, width, Height).Scale * Zoom:0.###}×원본";
        TextRenderer.DrawText(g, $"{label}{time}{dimensions}{scale} · 3× 게임 크기(192→576px) · 줌 {Zoom * 100:0}%", Font, new Rectangle(left + 8, 7, Math.Max(10, width - 16), 38), Color.White, TextFormatFlags.EndEllipsis | TextFormatFlags.VerticalCenter);
    }
    private RenderBox GetBox(Image image, int left, int width, int height)
    {
        float fit = Math.Min(576f / Math.Max(image.Width, image.Height), Math.Min(Math.Max(1, width - 28f) / image.Width, Math.Max(1, height - 58f) / image.Height));
        float scale = fit * Zoom, w = image.Width * scale, h = image.Height * scale;
        float baseTop = 42f + (height - 58f - h) / 2f; // Keep the full source in view; draw the anchor at its actual normalized position.
        float x = left + (width - w) / 2f + pan.X;
        float y = baseTop + pan.Y;
        return new RenderBox(new RectangleF(x, y, w, h), scale, y + (float)anchor.Y * h);
    }
    private static void DrawAnchorLine(Graphics g, float y, int left, int width)
    {
        using var pen = new Pen(Color.FromArgb(120, Color.Gold), 1) { DashStyle = DashStyle.Dash };
        g.DrawLine(pen, left, y, left + width, y);
    }
    private static void DrawAnchor(Graphics g, RenderBox renderBox, FootAnchor anchor, bool flip, string label)
    {
        RectangleF box = renderBox.Bounds;
        float ax = box.Left + (float)(flip ? 1 - anchor.X : anchor.X) * box.Width, ay = box.Top + (float)anchor.Y * box.Height;
        using var pen = new Pen(Color.Gold, 2); g.DrawLine(pen, ax - 9, ay, ax + 9, ay); g.DrawLine(pen, ax, ay - 9, ax, ay + 9); g.DrawEllipse(pen, ax - 5, ay - 5, 10, 10);
        if (label.Length > 0) TextRenderer.DrawText(g, label, SystemFonts.MessageBoxFont, new Point((int)ax + 7, (int)ay - 19), Color.Gold);
    }
    private static void DrawImage(Graphics g, Image image, RenderBox renderBox, bool flip, float alpha)
    {
        RectangleF box = renderBox.Bounds;
        var state = g.Save();
        if (flip) { g.TranslateTransform(box.Left * 2 + box.Width, 0); g.ScaleTransform(-1, 1); }
        using var attributes = new System.Drawing.Imaging.ImageAttributes();
        var matrix = new System.Drawing.Imaging.ColorMatrix { Matrix33 = alpha }; attributes.SetColorMatrix(matrix, System.Drawing.Imaging.ColorMatrixFlag.Default, System.Drawing.Imaging.ColorAdjustType.Bitmap);
        g.DrawImage(image, Rectangle.Round(box), 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attributes); g.Restore(state);
    }
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e); if (e.Button != MouseButtons.Left) return;
        dragging = true; dragOrigin = e.Location; panOrigin = pan; Capture = true;
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e); if (!dragging) return;
        pan = new Point(panOrigin.X + e.X - dragOrigin.X, panOrigin.Y + e.Y - dragOrigin.Y); Invalidate();
    }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); dragging = false; Capture = false; }
    internal void SimulateDrag(Point delta)
    {
        OnMouseDown(new MouseEventArgs(MouseButtons.Left, 1, 100, 100, 0));
        OnMouseMove(new MouseEventArgs(MouseButtons.Left, 1, 100 + delta.X, 100 + delta.Y, 0));
        OnMouseUp(new MouseEventArgs(MouseButtons.Left, 1, 100 + delta.X, 100 + delta.Y, 0));
    }
    protected override void Dispose(bool disposing) { if (disposing) { current?.Dispose(); comparison?.Dispose(); } base.Dispose(disposing); }
}
