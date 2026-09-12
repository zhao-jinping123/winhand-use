# 编译基准测试靶标为无控制台 WinExe。
# 首次运行会生成 sandbox-form.exe 与 cover-window.exe（已加入 .gitignore）。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$sandbox = @'
using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

public class BenchForm : Form
{
    private readonly string effectPath;
    private readonly string markerPath;
    private TextBox boxA;
    private TextBox boxB;
    private Label stateLabel;
    private CanvasPanel canvas;

    public BenchForm(string effectPath, string markerPath)
    {
        this.effectPath = effectPath;
        this.markerPath = markerPath;
        Text = "winhand-bench-sandbox";
        Width = 760;
        Height = 470;
        StartPosition = FormStartPosition.Manual;
        var area = Screen.PrimaryScreen.WorkingArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Top + (area.Height - Height) / 2;
        BackColor = Color.FromArgb(28, 30, 38);
        ForeColor = Color.WhiteSmoke;
        Font = new Font("Microsoft YaHei UI", 10F);

        boxA = new TextBox();
        boxA.Name = "inputA";
        boxA.Text = "A-initial";
        boxA.SetBounds(24, 40, 300, 30);

        boxB = new TextBox();
        boxB.Name = "inputB";
        boxB.Text = "B-initial";
        boxB.SetBounds(24, 92, 300, 30);

        Button go = new Button();
        go.Name = "goButton";
        go.Text = "提交并落盘";
        go.SetBounds(24, 146, 150, 40);
        go.Click += delegate { SaveEffect(); };

        stateLabel = new Label();
        stateLabel.Name = "stateLabel";
        stateLabel.Text = "state=idle";
        stateLabel.SetBounds(24, 210, 300, 28);
        stateLabel.ForeColor = Color.FromArgb(120, 220, 160);

        canvas = new CanvasPanel();
        canvas.Name = "canvasLayer";
        canvas.SetBounds(370, 36, 330, 340);
        canvas.MouseDown += delegate (object sender, MouseEventArgs e)
        {
            if (canvas.HitTarget(e.X, e.Y))
            {
                stateLabel.Text = "state=canvas-hit";
                if (!string.IsNullOrEmpty(markerPath))
                {
                    File.WriteAllText(markerPath, "canvas-hit");
                }
            }
        };

        Controls.Add(boxA);
        Controls.Add(boxB);
        Controls.Add(go);
        Controls.Add(stateLabel);
        Controls.Add(canvas);
    }

    private void SaveEffect()
    {
        stateLabel.Text = "state=saved";
        string body =
            "inputA=" + boxA.Text + Environment.NewLine +
            "inputB=" + boxB.Text + Environment.NewLine +
            "state=saved" + Environment.NewLine +
            "ts=" + DateTime.UtcNow.ToString("o");
        File.WriteAllText(effectPath, body);
    }

    [STAThread]
    public static void Main(string[] args)
    {
        string effect = args.Length > 0 ? args[0] : Path.Combine(Path.GetTempPath(), "winhand-bench-effect.txt");
        string marker = args.Length > 1 ? args[1] : "";
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new BenchForm(effect, marker));
    }
}

public class CanvasPanel : Panel
{
    public CanvasPanel()
    {
        DoubleBuffered = true;
        BackColor = Color.FromArgb(18, 20, 26);
    }

    public bool HitTarget(int x, int y)
    {
        return x >= 30 && x <= 110 && y >= 30 && y <= 110;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.Clear(BackColor);
        using (Pen grid = new Pen(Color.FromArgb(48, 54, 70)))
        {
            for (int i = 0; i < Width; i += 30)
            {
                e.Graphics.DrawLine(grid, i, 0, i, Height);
            }
            for (int j = 0; j < Height; j += 30)
            {
                e.Graphics.DrawLine(grid, 0, j, Width, j);
            }
        }
        using (Brush fill = new SolidBrush(Color.FromArgb(255, 150, 60)))
        {
            e.Graphics.FillRectangle(fill, 30, 30, 80, 80);
        }
        using (Brush text = new SolidBrush(Color.WhiteSmoke))
        {
            e.Graphics.DrawString("坐标靶心（无 UIA）", Font, text, 28, 126);
            e.Graphics.DrawString("纯自绘控件：只能走坐标层", Font, text, 28, 158);
        }
    }
}
'@

$cover = @'
using System;
using System.Drawing;
using System.Windows.Forms;

public class CoverForm : Form
{
    public CoverForm(int left, int top, int width, int height)
    {
        Text = "winhand-bench-cover";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        SetBounds(left, top, width, height);
        TopMost = true;
        BackColor = Color.FromArgb(12, 14, 18);
        var label = new Label();
        label.Dock = DockStyle.Fill;
        label.TextAlign = ContentAlignment.MiddleCenter;
        label.ForeColor = Color.FromArgb(255, 190, 90);
        label.Font = new Font("Microsoft YaHei UI", 18F, FontStyle.Bold);
        label.Text = "遮挡层：下面是被完全盖住的沙箱窗口\n（验证 PrintWindow 后台截图）";
        Controls.Add(label);
    }

    [STAThread]
    public static void Main(string[] args)
    {
        int left = args.Length > 0 ? int.Parse(args[0]) : 0;
        int top = args.Length > 1 ? int.Parse(args[1]) : 0;
        int width = args.Length > 2 ? int.Parse(args[2]) : 760;
        int height = args.Length > 3 ? int.Parse(args[3]) : 470;
        Application.EnableVisualStyles();
        Application.Run(new CoverForm(left, top, width, height));
    }
}
'@

$sandboxExe = Join-Path $here 'sandbox-form.exe'
$coverExe = Join-Path $here 'cover-window.exe'
if (-not (Test-Path $sandboxExe)) {
    Add-Type -TypeDefinition $sandbox -ReferencedAssemblies System.Windows.Forms, System.Drawing -OutputAssembly $sandboxExe -OutputType WindowsApplication
}
if (-not (Test-Path $coverExe)) {
    Add-Type -TypeDefinition $cover -ReferencedAssemblies System.Windows.Forms, System.Drawing -OutputAssembly $coverExe -OutputType WindowsApplication
}
Write-Output ('sandbox_exe=' + (Test-Path $sandboxExe))
Write-Output ('cover_exe=' + (Test-Path $coverExe))
