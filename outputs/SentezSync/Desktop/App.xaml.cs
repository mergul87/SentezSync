using System.Windows;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace SentezSync;
public partial class App : Application {
 System.Threading.Mutex? instanceMutex;
 bool ownsMutex;
 protected override void OnStartup(StartupEventArgs e){
  instanceMutex=new System.Threading.Mutex(true,"Local\\SentezSync-Desktop",out ownsMutex);
  if(!ownsMutex){MessageBox.Show("SentezSync zaten açık. Açık pencereyi kullanın.");Shutdown();return;}
  if(e.Args.Length>=2 && e.Args[0]=="--render"){
   var window=new MainWindow();MainWindow=window;window.Show();if(e.Args.Length>2 && int.TryParse(e.Args[2],out var tab))((System.Windows.Controls.TabControl)window.FindName("MainTabs")).SelectedIndex=tab;
   window.Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle,new Action(()=>{
    try{window.UpdateLayout();var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(window);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var stream=File.Create(e.Args[1]);encoder.Save(stream);}
    finally{Shutdown();}
   }));
  }
  else { var window=new MainWindow(); MainWindow=window; window.Show(); }
  base.OnStartup(e);
 }
 protected override void OnExit(ExitEventArgs e){if(ownsMutex)instanceMutex?.ReleaseMutex();instanceMutex?.Dispose();base.OnExit(e);}
}



