param([switch]$SelfTest, [switch]$ReadKey, [int]$ParentProcessId = 0)
$ErrorActionPreference = 'Stop'
if ($ReadKey) {
    $key = [string](Get-Clipboard -Raw)
    $key = $key.Trim()
    if ($key -cmatch '^(?:AQ\.)?[A-Za-z0-9_-]{20,300}={0,2}$') { [Console]::Write($key) }
    exit 0
}
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class NibOpticalCapture {
    const int Columns=64, Rows=24;
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd,out Rect rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hwnd,ref Point point);
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left,Top,Right,Bottom; }
    static readonly int[] Marker = {5,2,7,1,6,3,0,4,3,6,1,7,2,5,4,0};
    static readonly byte[] Magic = System.Text.Encoding.ASCII.GetBytes("NIBPIX2!");
    static readonly int[] Sizes = {2,1,3,4};
    static int cachedX=-1,cachedY=-1,cachedSize=2;
    static IntPtr lastWindow=IntPtr.Zero;

    static int Sample(Bitmap bmp,int x,int y) {
        Color c=bmp.GetPixel(x,y);
        return (c.R+c.G+c.B)/3;
    }
    static int[] Calibrate(Bitmap bmp,int x,int y,int size) {
        if(x<0||y<0||x+Columns*size>bmp.Width||y+(Rows+1)*size>bmp.Height) return null;
        int[] values=new int[8];
        for(int i=0;i<8;i++) values[Marker[i]]=Sample(bmp,x+i*size+size/2,y+size/2);
        for(int i=1;i<8;i++) if(values[i]-values[i-1]<7) return null;
        for(int i=8;i<Marker.Length;i++)
            if(Math.Abs(Sample(bmp,x+i*size+size/2,y+size/2)-values[Marker[i]])>5) return null;
        return values;
    }
    static byte[] DecodeAt(Bitmap bmp,int x,int y,int size) {
        int[] values=Calibrate(bmp,x,y,size);
        if(values==null) return null;
        byte[] result=new byte[Columns*Rows*3/8];
        int bit=0;
        for(int row=0;row<Rows;row++) for(int col=0;col<Columns;col++) {
            int gray=Sample(bmp,x+col*size+size/2,y+(row+1)*size+size/2);
            int value=0;
            while(value<7 && gray*2>values[value]+values[value+1]) value++;
            for(int k=2;k>=0;k--){
                if(((value>>k)&1)!=0) result[bit/8]|=(byte)(1<<(7-bit%8));
                bit++;
                if(bit%8==0 && bit/8<=Magic.Length && result[bit/8-1]!=Magic[bit/8-1]) return null;
            }
        }
        return result;
    }
    static byte[] Find(Bitmap bmp) {
        byte[] bytes=DecodeAt(bmp,cachedX,cachedY,cachedSize);
        if(bytes!=null) return bytes;
        foreach(int size in Sizes) {
            int right=bmp.Width-Columns*size,bottom=bmp.Height-(Rows+1)*size;
            for(int y=bottom;y>=Math.Max(0,bottom-12);y--) for(int x=right;x>=Math.Max(0,right-12);x--) {
                bytes=DecodeAt(bmp,x,y,size);
                if(bytes!=null) { cachedX=x;cachedY=y;cachedSize=size;return bytes; }
            }
        }
        return null;
    }
    public static string Capture() {
        IntPtr hwnd=GetForegroundWindow();
        uint pid; GetWindowThreadProcessId(hwnd,out pid);
        if(pid==0) return null;
        try {
            if(!Process.GetProcessById((int)pid).ProcessName.StartsWith("Wow",StringComparison.OrdinalIgnoreCase)) return null;
        } catch { return null; }
        if(lastWindow!=hwnd) { cachedX=-1;cachedY=-1;lastWindow=hwnd; }
        Rect rect; if(!GetClientRect(hwnd,out rect)) return null;
        Point origin=new Point(rect.Right,rect.Bottom);
        if(!ClientToScreen(hwnd,ref origin)) return null;
        int width=Math.Min(280,rect.Right),height=Math.Min(115,rect.Bottom);
        if(width<128||height<50) return null;
        using(Bitmap bitmap=new Bitmap(width,height,System.Drawing.Imaging.PixelFormat.Format32bppArgb)) {
            using(Graphics gfx=Graphics.FromImage(bitmap)) gfx.CopyFromScreen(origin.X-width,origin.Y-height,0,0,new Size(width,height),CopyPixelOperation.SourceCopy);
            byte[] bytes=Find(bitmap);
            return bytes==null?null:Convert.ToBase64String(bytes);
        }
    }
    public static bool SelfTest() {
        byte[] expected=new byte[Columns*Rows*3/8];
        new Random(7).NextBytes(expected);
        Array.Copy(Magic,expected,Magic.Length);
        foreach(int size in Sizes) {
            using(Bitmap bitmap=new Bitmap(280,115)) using(Graphics gfx=Graphics.FromImage(bitmap)) {
                int x=bitmap.Width-Columns*size-4,y=bitmap.Height-(Rows+1)*size-3;
                for(int i=0;i<Columns;i++) using(var b=new SolidBrush(Palette(Marker[i%16]))) gfx.FillRectangle(b,x+i*size,y,size,size);
                for(int cell=0;cell<Columns*Rows;cell++) {
                    int value=0;
                    for(int i=0;i<3;i++){int bit=cell*3+i;value=value*2+((expected[bit/8]>>(7-bit%8))&1);}
                    using(var b=new SolidBrush(Palette(value))) gfx.FillRectangle(b,x+(cell%Columns)*size,y+(cell/Columns+1)*size,size,size);
                }
                byte[] actual=Find(bitmap);
                if(actual==null) return false;
                for(int i=0;i<expected.Length;i++) if(actual[i]!=expected[i]) return false;
            }
        }
        return true;
    }
    static Color Palette(int value) {
        int gray=(int)(230*Math.Pow((24+value*24)/255.0,0.78))+8;
        return Color.FromArgb(gray,gray,gray);
    }
    public static void Init() {
        try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch {}
    }
}
'@ -ReferencedAssemblies System.Drawing,System.Core
if ($SelfTest) {
    if (-not [NibOpticalCapture]::SelfTest()) { throw 'Optical codec self-test failed.' }
    Write-Output 'Compact corner transport passed at one through four pixels per cell. No desktop capture performed.'
    exit 0
}
[NibOpticalCapture]::Init()
$iteration = 0
while ($true) {
    if ($ParentProcessId -gt 0 -and ($iteration % 30) -eq 0) {
        if (-not (Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue)) { break }
    }
    try {
        $frame = [NibOpticalCapture]::Capture()
        if ($frame) { Write-Output $frame }
    } catch {
        if ($iteration % 30 -eq 0) { [Console]::Error.WriteLine('Nib capture: ' + $_.Exception.Message) }
    }
    $iteration++
    Start-Sleep -Milliseconds 65
}
