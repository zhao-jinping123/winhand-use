# winhand-use 基准测试靶标：可 UIA 操作的 WinForms 窗口。
# 输入框可用 UIA 后台写入，按钮用 UIA Invoke 触发并落盘副作用；
# 右侧画布为纯自绘控件（无 UIA 可编辑元素），用于坐标层测试。
param(
    [Parameter(Mandatory = $true)][string]$EffectPath,
    [string]$MarkerPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$code = @"
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
        boxA.Text = "A-初始";
        boxA.SetBounds(24, 40, 300, 30);

        boxB = new TextBox();
        boxB.Name = "inputB";
        boxB.Text = "B-初始";
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
"@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms, System.Drawing
$form = New-Object BenchForm($EffectPath, $MarkerPath)
[System.Windows.Forms.Application]::Run($form)
