# winhand-use 基准测试靶标：置顶遮挡层，用于验证“被遮挡也能后台截图”。
param(
    [int]$Left = 0,
    [int]$Top = 0,
    [int]$Width = 760,
    [int]$Height = 470
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$code = @"
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
}
"@

Add-Type -TypeDefinition $code -ReferencedAssemblies System.Windows.Forms, System.Drawing
$form = New-Object CoverForm($Left, $Top, $Width, $Height)
[System.Windows.Forms.Application]::Run($form)
