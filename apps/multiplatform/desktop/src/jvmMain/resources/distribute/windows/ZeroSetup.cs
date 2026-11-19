using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace ZeroSetup
{
    internal static partial class SetupManifest
    {
        public static string ExpectedMsiSha256
        {
            get
            {
                string val = "";
                ResolveExpectedMsiSha256(ref val);
                return val;
            }
        }

        static partial void ResolveExpectedMsiSha256(ref string value);
    }

    public class SetupApp : Application
    {
        private const string AppVersion = "1.0.0";
        private Window _window;
        private Border _welcomePane;
        private Border _progressPane;
        private Border _completePane;
        private Border _errorPane;
        private Border _customPanel;
        private TextBox _dirBox;
        private CheckBox _desktopShortcutCheck;
        private CheckBox _startMenuShortcutCheck;
        private TextBlock _statusLabel;
        private TextBlock _percentLabel;
        private Border _progressFill;
        private TextBlock _completePathLabel;
        private TextBlock _errorDetailLabel;
        private DispatcherTimer _progressTimer;
        private double _targetProgress;
        private double _currentProgress;
        private string _installDir;
        private bool _installing;

        [STAThread]
        public static int Main(string[] args)
        {
            if (args != null)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    string a = (args[i] ?? "").ToLowerInvariant();
                    if (a == "/s" || a == "-s" || a == "--silent" || a == "/silent" || a == "/quiet")
                    {
                        return RunSilentInstall();
                    }
                }
            }

            SetupApp app = new SetupApp();
            return app.Run();
        }

        private static int RunSilentInstall()
        {
            string tempDir = CreateIsolatedStagingDir();
            try
            {
                Directory.CreateDirectory(tempDir);
                string msiPath = ExtractAndVerifyMsi(tempDir);
                ProcessStartInfo psi = new ProcessStartInfo("msiexec.exe", "/i \"" + msiPath + "\" /qn /norestart");
                psi.UseShellExecute = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch
            {
                return 1;
            }
            finally
            {
                TryDeleteDir(tempDir);
            }
        }

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            _installDir = System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "Zero"
            );

            _window = new Window();
            _window.Title = "Zero Setup";
            _window.Width = 600;
            _window.Height = 436;
            _window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            _window.ResizeMode = ResizeMode.NoResize;
            _window.WindowStyle = WindowStyle.None;
            _window.AllowsTransparency = true;
            _window.Background = Brushes.Transparent;

            Border rootShell = new Border();
            rootShell.Margin = new Thickness(12);
            rootShell.CornerRadius = new CornerRadius(18);
            rootShell.Background = BrushFromHex("#000000");
            rootShell.BorderBrush = BrushFromHex("#242426");
            rootShell.BorderThickness = new Thickness(1);
            DropShadowEffect shadow = new DropShadowEffect();
            shadow.Color = Colors.Black;
            shadow.BlurRadius = 22;
            shadow.ShadowDepth = 6;
            shadow.Opacity = 0.65;
            rootShell.Effect = shadow;

            Grid shellGrid = new Grid();
            shellGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(52) });
            shellGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            // Top Chrome Bar
            Grid header = BuildHeader();
            Grid.SetRow(header, 0);
            shellGrid.Children.Add(header);

            // Body container
            Grid body = new Grid();
            body.Margin = new Thickness(34, 4, 34, 28);
            Grid.SetRow(body, 1);

            _welcomePane = BuildWelcomePane();
            _progressPane = BuildProgressPane();
            _completePane = BuildCompletePane();
            _errorPane = BuildErrorPane();

            _progressPane.Visibility = Visibility.Collapsed;
            _completePane.Visibility = Visibility.Collapsed;
            _errorPane.Visibility = Visibility.Collapsed;

            body.Children.Add(_welcomePane);
            body.Children.Add(_progressPane);
            body.Children.Add(_completePane);
            body.Children.Add(_errorPane);

            shellGrid.Children.Add(body);
            rootShell.Child = shellGrid;
            _window.Content = rootShell;
            _window.Show();
        }

        private Grid BuildHeader()
        {
            Grid header = new Grid();
            header.Background = Brushes.Transparent;
            header.MouseLeftButtonDown += delegate(object sender, MouseButtonEventArgs e)
            {
                if (e.ChangedButton == MouseButton.Left)
                {
                    try { _window.DragMove(); } catch { }
                }
            };

            StackPanel left = new StackPanel();
            left.Orientation = Orientation.Horizontal;
            left.VerticalAlignment = VerticalAlignment.Center;
            left.Margin = new Thickness(22, 0, 0, 0);

            Image miniLogo = CreateWordmarkImage(16);
            miniLogo.Margin = new Thickness(0, 0, 10, 0);
            left.Children.Add(miniLogo);

            Border versionPill = new Border();
            versionPill.CornerRadius = new CornerRadius(99);
            versionPill.Background = BrushFromHex("#121214");
            versionPill.BorderBrush = BrushFromHex("#262629");
            versionPill.BorderThickness = new Thickness(1);
            versionPill.Padding = new Thickness(8, 2, 8, 2);
            versionPill.VerticalAlignment = VerticalAlignment.Center;

            TextBlock verTxt = new TextBlock();
            verTxt.Text = "v" + AppVersion + " · x64";
            verTxt.FontFamily = new FontFamily("Consolas, Segoe UI");
            verTxt.FontSize = 10;
            verTxt.Foreground = BrushFromHex("#8E8E93");
            versionPill.Child = verTxt;
            left.Children.Add(versionPill);

            header.Children.Add(left);

            StackPanel right = new StackPanel();
            right.Orientation = Orientation.Horizontal;
            right.HorizontalAlignment = HorizontalAlignment.Right;
            right.VerticalAlignment = VerticalAlignment.Center;
            right.Margin = new Thickness(0, 0, 14, 0);

            Button minBtn = CreateChromeButton("—");
            minBtn.Click += delegate { _window.WindowState = WindowState.Minimized; };
            Button closeBtn = CreateChromeButton("×");
            closeBtn.FontSize = 16;
            closeBtn.Click += delegate { if (!_installing) _window.Close(); };

            right.Children.Add(minBtn);
            right.Children.Add(closeBtn);
            header.Children.Add(right);

            return header;
        }

        private Button CreateChromeButton(string glyph)
        {
            Button b = new Button();
            b.Content = glyph;
            b.Width = 30;
            b.Height = 28;
            b.FontFamily = new FontFamily("Segoe UI");
            b.FontSize = 13;
            b.Foreground = BrushFromHex("#8E8E93");
            b.Background = Brushes.Transparent;
            b.BorderThickness = new Thickness(0);
            b.Cursor = Cursors.Hand;
            b.Style = CreateFlatButtonStyle("#00000000", "#1A1A1D", "#8E8E93", "#FFFFFF", 8);
            return b;
        }

        private Border BuildWelcomePane()
        {
            Border wrap = new Border();
            Grid grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            StackPanel hero = new StackPanel();
            hero.VerticalAlignment = VerticalAlignment.Center;
            hero.HorizontalAlignment = HorizontalAlignment.Center;

            Image wordmark = CreateWordmarkImage(40);
            wordmark.HorizontalAlignment = HorizontalAlignment.Center;
            wordmark.Margin = new Thickness(0, 0, 0, 16);
            hero.Children.Add(wordmark);

            TextBlock title = new TextBlock();
            title.Text = "Privacy Should Be Effortless.";
            title.FontFamily = new FontFamily("Segoe UI");
            title.FontSize = 20;
            title.FontWeight = FontWeights.SemiBold;
            title.Foreground = Brushes.White;
            title.HorizontalAlignment = HorizontalAlignment.Center;
            title.Margin = new Thickness(0, 0, 0, 8);
            hero.Children.Add(title);

            TextBlock sub = new TextBlock();
            sub.Text = "Post-quantum encrypted messaging with zero phone numbers, zero emails, and zero persistent identifiers.";
            sub.FontFamily = new FontFamily("Segoe UI");
            sub.FontSize = 12.5;
            sub.Foreground = BrushFromHex("#8E8E93");
            sub.TextWrapping = TextWrapping.Wrap;
            sub.TextAlignment = TextAlignment.Center;
            sub.MaxWidth = 430;
            sub.Margin = new Thickness(0, 0, 0, 18);
            hero.Children.Add(sub);

            StackPanel pills = new StackPanel();
            pills.Orientation = Orientation.Horizontal;
            pills.HorizontalAlignment = HorizontalAlignment.Center;
            pills.Margin = new Thickness(0, 0, 0, 12);
            pills.Children.Add(CreateSpecPill("Curve448 + sntrup761"));
            pills.Children.Add(CreateSpecPill("16 KB Padded"));
            pills.Children.Add(CreateSpecPill("2-Hop Onion"));
            hero.Children.Add(pills);

            // Collapsible customize panel
            _customPanel = new Border();
            _customPanel.Visibility = Visibility.Collapsed;
            _customPanel.Background = BrushFromHex("#0A0A0C");
            _customPanel.BorderBrush = BrushFromHex("#1F1F22");
            _customPanel.BorderThickness = new Thickness(1);
            _customPanel.CornerRadius = new CornerRadius(12);
            _customPanel.Padding = new Thickness(14, 10, 14, 10);
            _customPanel.Margin = new Thickness(0, 4, 0, 6);
            _customPanel.Width = 468;

            StackPanel customStack = new StackPanel();
            Grid pathRow = new Grid();
            pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            pathRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            _dirBox = new TextBox();
            _dirBox.Text = _installDir;
            _dirBox.FontFamily = new FontFamily("Consolas, Segoe UI");
            _dirBox.FontSize = 11.5;
            _dirBox.Foreground = Brushes.White;
            _dirBox.Background = BrushFromHex("#141416");
            _dirBox.BorderBrush = BrushFromHex("#2A2A2E");
            _dirBox.BorderThickness = new Thickness(1);
            _dirBox.Padding = new Thickness(8, 5, 8, 5);
            _dirBox.Margin = new Thickness(0, 0, 8, 0);
            Grid.SetColumn(_dirBox, 0);
            pathRow.Children.Add(_dirBox);

            Button browseBtn = new Button();
            browseBtn.Content = "Browse";
            browseBtn.FontFamily = new FontFamily("Segoe UI");
            browseBtn.FontSize = 11.5;
            browseBtn.Padding = new Thickness(12, 5, 12, 5);
            browseBtn.Cursor = Cursors.Hand;
            browseBtn.Style = CreateFlatButtonStyle("#18181B", "#27272A", "#FFFFFF", "#FFFFFF", 8);
            browseBtn.Click += delegate
            {
                using (System.Windows.Forms.FolderBrowserDialog dlg = new System.Windows.Forms.FolderBrowserDialog())
                {
                    dlg.SelectedPath = _dirBox.Text;
                    dlg.Description = "Select Zero installation folder";
                    if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK && !string.IsNullOrEmpty(dlg.SelectedPath))
                    {
                        _dirBox.Text = System.IO.Path.Combine(dlg.SelectedPath, "Zero");
                    }
                }
            };
            Grid.SetColumn(browseBtn, 1);
            pathRow.Children.Add(browseBtn);
            customStack.Children.Add(pathRow);

            StackPanel checks = new StackPanel();
            checks.Orientation = Orientation.Horizontal;
            checks.Margin = new Thickness(0, 8, 0, 0);
            _desktopShortcutCheck = CreateMonochromeCheck("Desktop shortcut", true);
            _desktopShortcutCheck.Margin = new Thickness(0, 0, 18, 0);
            _startMenuShortcutCheck = CreateMonochromeCheck("Start Menu shortcut", true);
            checks.Children.Add(_desktopShortcutCheck);
            checks.Children.Add(_startMenuShortcutCheck);
            customStack.Children.Add(checks);

            _customPanel.Child = customStack;
            hero.Children.Add(_customPanel);

            Grid.SetRow(hero, 0);
            grid.Children.Add(hero);

            // Footer action bar
            Grid footer = new Grid();
            footer.Margin = new Thickness(0, 10, 0, 0);
            footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Button customToggle = new Button();
            customToggle.Content = "Install options";
            customToggle.FontFamily = new FontFamily("Segoe UI");
            customToggle.FontSize = 12;
            customToggle.Padding = new Thickness(14, 9, 14, 9);
            customToggle.Cursor = Cursors.Hand;
            customToggle.Style = CreateFlatButtonStyle("#0A0A0C", "#161618", "#8E8E93", "#FFFFFF", 99);
            customToggle.Click += delegate
            {
                bool show = _customPanel.Visibility != Visibility.Visible;
                _customPanel.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
                customToggle.Content = show ? "Hide options" : "Install options";
            };
            Grid.SetColumn(customToggle, 0);
            footer.Children.Add(customToggle);

            Button installBtn = new Button();
            installBtn.Content = "Install Zero";
            installBtn.FontFamily = new FontFamily("Segoe UI");
            installBtn.FontSize = 14;
            installBtn.FontWeight = FontWeights.SemiBold;
            installBtn.Padding = new Thickness(28, 11, 28, 11);
            installBtn.Cursor = Cursors.Hand;
            installBtn.Style = CreateFlatButtonStyle("#FFFFFF", "#E5E5EA", "#000000", "#000000", 99);
            installBtn.Click += delegate { StartInstall(); };
            Grid.SetColumn(installBtn, 2);
            footer.Children.Add(installBtn);

            Grid.SetRow(footer, 1);
            grid.Children.Add(footer);
            wrap.Child = grid;
            return wrap;
        }

        private Border BuildProgressPane()
        {
            Border wrap = new Border();
            StackPanel stack = new StackPanel();
            stack.VerticalAlignment = VerticalAlignment.Center;
            stack.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Width = 420;

            Image wordmark = CreateWordmarkImage(34);
            wordmark.HorizontalAlignment = HorizontalAlignment.Center;
            wordmark.Margin = new Thickness(0, 0, 0, 26);
            stack.Children.Add(wordmark);

            Grid labelRow = new Grid();
            labelRow.Margin = new Thickness(0, 0, 0, 10);
            _statusLabel = new TextBlock();
            _statusLabel.Text = "Preparing installation…";
            _statusLabel.FontFamily = new FontFamily("Segoe UI");
            _statusLabel.FontSize = 13;
            _statusLabel.Foreground = BrushFromHex("#D1D1D6");
            _statusLabel.HorizontalAlignment = HorizontalAlignment.Left;

            _percentLabel = new TextBlock();
            _percentLabel.Text = "0%";
            _percentLabel.FontFamily = new FontFamily("Consolas, Segoe UI");
            _percentLabel.FontSize = 12;
            _percentLabel.Foreground = BrushFromHex("#8E8E93");
            _percentLabel.HorizontalAlignment = HorizontalAlignment.Right;

            labelRow.Children.Add(_statusLabel);
            labelRow.Children.Add(_percentLabel);
            stack.Children.Add(labelRow);

            Border track = new Border();
            track.Height = 5;
            track.CornerRadius = new CornerRadius(3);
            track.Background = BrushFromHex("#1A1A1D");
            track.HorizontalAlignment = HorizontalAlignment.Stretch;

            _progressFill = new Border();
            _progressFill.Height = 5;
            _progressFill.CornerRadius = new CornerRadius(3);
            _progressFill.Background = Brushes.White;
            _progressFill.HorizontalAlignment = HorizontalAlignment.Left;
            _progressFill.Width = 0;

            track.Child = _progressFill;
            stack.Children.Add(track);

            TextBlock note = new TextBlock();
            note.Text = "Verifying cryptographic runtime and creating local encrypted environment";
            note.FontFamily = new FontFamily("Segoe UI");
            note.FontSize = 11.5;
            note.Foreground = BrushFromHex("#636366");
            note.HorizontalAlignment = HorizontalAlignment.Center;
            note.Margin = new Thickness(0, 14, 0, 0);
            stack.Children.Add(note);

            wrap.Child = stack;
            return wrap;
        }

        private Border BuildCompletePane()
        {
            Border wrap = new Border();
            Grid grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            StackPanel center = new StackPanel();
            center.VerticalAlignment = VerticalAlignment.Center;
            center.HorizontalAlignment = HorizontalAlignment.Center;

            Grid badge = new Grid();
            badge.Width = 56;
            badge.Height = 56;
            badge.Margin = new Thickness(0, 0, 0, 18);

            Ellipse ring = new Ellipse();
            ring.Width = 56;
            ring.Height = 56;
            ring.Stroke = Brushes.White;
            ring.StrokeThickness = 2;
            ring.Fill = BrushFromHex("#0D0D0F");
            badge.Children.Add(ring);

            System.Windows.Shapes.Path check = new System.Windows.Shapes.Path();
            check.Stroke = Brushes.White;
            check.StrokeThickness = 2.6;
            check.StrokeStartLineCap = PenLineCap.Round;
            check.StrokeEndLineCap = PenLineCap.Round;
            check.StrokeLineJoin = PenLineJoin.Round;
            check.Data = Geometry.Parse("M 18,29 L 25,36 L 39,21");
            badge.Children.Add(check);
            center.Children.Add(badge);

            TextBlock doneTitle = new TextBlock();
            doneTitle.Text = "Zero is ready.";
            doneTitle.FontFamily = new FontFamily("Segoe UI");
            doneTitle.FontSize = 22;
            doneTitle.FontWeight = FontWeights.SemiBold;
            doneTitle.Foreground = Brushes.White;
            doneTitle.HorizontalAlignment = HorizontalAlignment.Center;
            doneTitle.Margin = new Thickness(0, 0, 0, 6);
            center.Children.Add(doneTitle);

            _completePathLabel = new TextBlock();
            _completePathLabel.FontFamily = new FontFamily("Segoe UI");
            _completePathLabel.FontSize = 12.5;
            _completePathLabel.Foreground = BrushFromHex("#8E8E93");
            _completePathLabel.HorizontalAlignment = HorizontalAlignment.Center;
            center.Children.Add(_completePathLabel);

            Grid.SetRow(center, 0);
            grid.Children.Add(center);

            StackPanel footer = new StackPanel();
            footer.Orientation = Orientation.Horizontal;
            footer.HorizontalAlignment = HorizontalAlignment.Right;

            Button closeBtn = new Button();
            closeBtn.Content = "Close";
            closeBtn.FontFamily = new FontFamily("Segoe UI");
            closeBtn.FontSize = 13;
            closeBtn.Padding = new Thickness(20, 10, 20, 10);
            closeBtn.Margin = new Thickness(0, 0, 10, 0);
            closeBtn.Cursor = Cursors.Hand;
            closeBtn.Style = CreateFlatButtonStyle("#121214", "#1F1F23", "#D1D1D6", "#FFFFFF", 99);
            closeBtn.Click += delegate { _window.Close(); };

            Button launchBtn = new Button();
            launchBtn.Content = "Launch Zero";
            launchBtn.FontFamily = new FontFamily("Segoe UI");
            launchBtn.FontSize = 14;
            launchBtn.FontWeight = FontWeights.SemiBold;
            launchBtn.Padding = new Thickness(28, 10, 28, 10);
            launchBtn.Cursor = Cursors.Hand;
            launchBtn.Style = CreateFlatButtonStyle("#FFFFFF", "#E5E5EA", "#000000", "#000000", 99);
            launchBtn.Click += delegate
            {
                LaunchInstalledApp();
                _window.Close();
            };

            footer.Children.Add(closeBtn);
            footer.Children.Add(launchBtn);
            Grid.SetRow(footer, 1);
            grid.Children.Add(footer);

            wrap.Child = grid;
            return wrap;
        }

        private Border BuildErrorPane()
        {
            Border wrap = new Border();
            Grid grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            StackPanel center = new StackPanel();
            center.VerticalAlignment = VerticalAlignment.Center;
            center.HorizontalAlignment = HorizontalAlignment.Center;
            center.MaxWidth = 440;

            TextBlock errTitle = new TextBlock();
            errTitle.Text = "Installation did not complete";
            errTitle.FontFamily = new FontFamily("Segoe UI");
            errTitle.FontSize = 19;
            errTitle.FontWeight = FontWeights.SemiBold;
            errTitle.Foreground = Brushes.White;
            errTitle.HorizontalAlignment = HorizontalAlignment.Center;
            errTitle.Margin = new Thickness(0, 0, 0, 8);
            center.Children.Add(errTitle);

            _errorDetailLabel = new TextBlock();
            _errorDetailLabel.FontFamily = new FontFamily("Segoe UI");
            _errorDetailLabel.FontSize = 12.5;
            _errorDetailLabel.Foreground = BrushFromHex("#8E8E93");
            _errorDetailLabel.TextWrapping = TextWrapping.Wrap;
            _errorDetailLabel.TextAlignment = TextAlignment.Center;
            center.Children.Add(_errorDetailLabel);

            Grid.SetRow(center, 0);
            grid.Children.Add(center);

            StackPanel footer = new StackPanel();
            footer.Orientation = Orientation.Horizontal;
            footer.HorizontalAlignment = HorizontalAlignment.Right;

            Button closeBtn = new Button();
            closeBtn.Content = "Close";
            closeBtn.FontFamily = new FontFamily("Segoe UI");
            closeBtn.FontSize = 13;
            closeBtn.Padding = new Thickness(20, 10, 20, 10);
            closeBtn.Margin = new Thickness(0, 0, 10, 0);
            closeBtn.Cursor = Cursors.Hand;
            closeBtn.Style = CreateFlatButtonStyle("#121214", "#1F1F23", "#D1D1D6", "#FFFFFF", 99);
            closeBtn.Click += delegate { _window.Close(); };

            Button retryBtn = new Button();
            retryBtn.Content = "Try Again";
            retryBtn.FontFamily = new FontFamily("Segoe UI");
            retryBtn.FontSize = 13.5;
            retryBtn.FontWeight = FontWeights.SemiBold;
            retryBtn.Padding = new Thickness(24, 10, 24, 10);
            retryBtn.Cursor = Cursors.Hand;
            retryBtn.Style = CreateFlatButtonStyle("#FFFFFF", "#E5E5EA", "#000000", "#000000", 99);
            retryBtn.Click += delegate { SwitchPane(_welcomePane); };

            footer.Children.Add(closeBtn);
            footer.Children.Add(retryBtn);
            Grid.SetRow(footer, 1);
            grid.Children.Add(footer);

            wrap.Child = grid;
            return wrap;
        }

        private void StartInstall()
        {
            if (_installing) return;

            string chosen = (_dirBox != null && !string.IsNullOrWhiteSpace(_dirBox.Text))
                ? _dirBox.Text.Trim()
                : _installDir;
            string validationError = ValidateInstallDir(chosen);
            if (validationError != null)
            {
                _errorDetailLabel.Text = validationError;
                SwitchPane(_errorPane);
                return;
            }
            _installDir = System.IO.Path.GetFullPath(chosen);
            _installing = true;

            _currentProgress = 0;
            _targetProgress = 18;
            _progressFill.Width = 0;
            _percentLabel.Text = "0%";
            _statusLabel.Text = "Preparing Windows Installer package…";
            SwitchPane(_progressPane);

            _progressTimer = new DispatcherTimer();
            _progressTimer.Interval = TimeSpan.FromMilliseconds(35);
            _progressTimer.Tick += delegate
            {
                if (_currentProgress < _targetProgress)
                {
                    _currentProgress = Math.Min(_targetProgress, _currentProgress + Math.Max(0.4, (_targetProgress - _currentProgress) * 0.08));
                    _progressFill.Width = 420.0 * (_currentProgress / 100.0);
                    _percentLabel.Text = ((int)Math.Round(_currentProgress)).ToString() + "%";
                }
            };
            _progressTimer.Start();

            Thread worker = new Thread(delegate()
            {
                string tempDir = CreateIsolatedStagingDir();
                try
                {
                    Directory.CreateDirectory(tempDir);
                    SetProgress(24, "Verifying Zero installer SHA-256 checksum…");
                    string msiPath = ExtractAndVerifyMsi(tempDir);

                    SetProgress(36, "Deploying Zero Core & Post-Quantum Runtime…");
                    string args = "/i \"" + msiPath + "\" /qn /norestart INSTALLDIR=\"" + _installDir + "\"";
                    ProcessStartInfo psi = new ProcessStartInfo("msiexec.exe", args);
                    psi.UseShellExecute = true;
                    psi.Verb = "runas";
                    psi.WindowStyle = ProcessWindowStyle.Hidden;

                    SetProgress(62, "Installing application files and shortcuts…");
                    using (Process proc = Process.Start(psi))
                    {
                        while (!proc.WaitForExit(350))
                        {
                            if (_targetProgress < 92)
                            {
                                SetProgress(_targetProgress + 2.5, "Installing Zero to " + _installDir + "…");
                            }
                        }

                        if (proc.ExitCode != 0 && proc.ExitCode != 3010)
                        {
                            throw new Exception("Windows Installer returned exit code " + proc.ExitCode + ".");
                        }
                    }

                    SetProgress(100, "Zero is installed.");
                    Thread.Sleep(350);

                    Dispatcher.Invoke(delegate
                    {
                        _progressTimer.Stop();
                        _installing = false;
                        _completePathLabel.Text = "Installed to " + _installDir;
                        SwitchPane(_completePane);
                    });
                }
                catch (Exception ex)
                {
                    Dispatcher.Invoke(delegate
                    {
                        _progressTimer.Stop();
                        _installing = false;
                        _errorDetailLabel.Text = ex.Message;
                        SwitchPane(_errorPane);
                    });
                }
                finally
                {
                    TryDeleteDir(tempDir);
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }

        private void SetProgress(double pct, string status)
        {
            Dispatcher.BeginInvoke(new Action(delegate
            {
                if (pct > _targetProgress) _targetProgress = Math.Min(100, pct);
                _statusLabel.Text = status;
            }));
        }

        private void SwitchPane(Border target)
        {
            _welcomePane.Visibility = target == _welcomePane ? Visibility.Visible : Visibility.Collapsed;
            _progressPane.Visibility = target == _progressPane ? Visibility.Visible : Visibility.Collapsed;
            _completePane.Visibility = target == _completePane ? Visibility.Visible : Visibility.Collapsed;
            _errorPane.Visibility = target == _errorPane ? Visibility.Visible : Visibility.Collapsed;

            DoubleAnimation fade = new DoubleAnimation(0.0, 1.0, TimeSpan.FromMilliseconds(180));
            target.BeginAnimation(UIElement.OpacityProperty, fade);
        }

        private void LaunchInstalledApp()
        {
            string exePath = System.IO.Path.Combine(_installDir, "Zero.exe");
            if (File.Exists(exePath))
            {
                ProcessStartInfo psi = new ProcessStartInfo(exePath);
                psi.UseShellExecute = true;
                psi.WorkingDirectory = _installDir;
                Process.Start(psi);
            }
        }

        private static string CreateIsolatedStagingDir()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(localAppData))
            {
                localAppData = System.IO.Path.GetTempPath();
            }
            return System.IO.Path.Combine(localAppData, "ZeroSetup", Guid.NewGuid().ToString("N"));
        }

        private static string ValidateInstallDir(string rawPath)
        {
            if (string.IsNullOrWhiteSpace(rawPath))
            {
                return "Installation folder cannot be empty.";
            }
            if (!System.IO.Path.IsPathRooted(rawPath))
            {
                return "Installation folder must be a full path (e.g. C:\\Program Files\\Zero).";
            }
            if (rawPath.Contains("..") || rawPath.IndexOfAny(new char[] { '"', ';', '|', '&' }) >= 0)
            {
                return "Installation folder contains unsupported path characters.";
            }
            for (int i = 0; i < rawPath.Length; i++)
            {
                if (char.IsControl(rawPath[i]))
                {
                    return "Installation folder contains invalid control characters.";
                }
            }
            try
            {
                System.IO.Path.GetFullPath(rawPath);
            }
            catch
            {
                return "Installation folder path is not valid.";
            }
            return null;
        }

        private static string ComputeSha256Hex(string filePath)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(filePath))
            {
                byte[] hash = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder(hash.Length * 2);
                for (int i = 0; i < hash.Length; i++)
                {
                    sb.Append(hash[i].ToString("x2"));
                }
                return sb.ToString();
            }
        }

        private static string ExtractAndVerifyMsi(string tempDir)
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string adjacentMsi = System.IO.Path.Combine(exeDir, "Zero.msi");
            string outMsi = System.IO.Path.Combine(tempDir, "Zero.msi");
            if (File.Exists(adjacentMsi))
            {
                File.Copy(adjacentMsi, outMsi, true);
            }
            else
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream("Zero.msi"))
                {
                    if (s == null)
                    {
                        throw new FileNotFoundException("Embedded Zero.msi installer payload was not found.");
                    }
                    using (FileStream fs = File.Create(outMsi))
                    {
                        s.CopyTo(fs);
                    }
                }
            }

            string expected = (SetupManifest.ExpectedMsiSha256 ?? "").Trim();
            if (!string.IsNullOrEmpty(expected))
            {
                string actual = ComputeSha256Hex(outMsi);
                if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("Installer integrity check failed (SHA-256 mismatch on Zero.msi).");
                }
            }
            return outMsi;
        }

        private static Image CreateWordmarkImage(double height)
        {
            Image img = new Image();
            img.Height = height;
            img.Stretch = Stretch.Uniform;
            RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream("ZeroWordmark.png"))
                {
                    if (s != null)
                    {
                        BitmapImage bmp = new BitmapImage();
                        bmp.BeginInit();
                        bmp.CacheOption = BitmapCacheOption.OnLoad;
                        bmp.StreamSource = s;
                        bmp.EndInit();
                        bmp.Freeze();
                        img.Source = bmp;
                    }
                }
            }
            catch { }
            return img;
        }

        private static Border CreateSpecPill(string text)
        {
            Border b = new Border();
            b.CornerRadius = new CornerRadius(99);
            b.Background = BrushFromHex("#0A0A0C");
            b.BorderBrush = BrushFromHex("#222226");
            b.BorderThickness = new Thickness(1);
            b.Padding = new Thickness(10, 4, 10, 4);
            b.Margin = new Thickness(4, 0, 4, 0);

            TextBlock t = new TextBlock();
            t.Text = text;
            t.FontFamily = new FontFamily("Segoe UI");
            t.FontSize = 10.5;
            t.Foreground = BrushFromHex("#A1A1A6");
            b.Child = t;
            return b;
        }

        private static CheckBox CreateMonochromeCheck(string label, bool isChecked)
        {
            CheckBox cb = new CheckBox();
            cb.Content = label;
            cb.IsChecked = isChecked;
            cb.Foreground = BrushFromHex("#D1D1D6");
            cb.FontFamily = new FontFamily("Segoe UI");
            cb.FontSize = 11.5;
            return cb;
        }

        private static Style CreateFlatButtonStyle(string bgHex, string hoverHex, string fgHex, string hoverFgHex, double radius)
        {
            Style style = new Style(typeof(Button));
            ControlTemplate tpl = new ControlTemplate(typeof(Button));
            FrameworkElementFactory bd = new FrameworkElementFactory(typeof(Border));
            bd.Name = "bd";
            bd.SetValue(Border.BackgroundProperty, BrushFromHex(bgHex));
            bd.SetValue(Border.CornerRadiusProperty, new CornerRadius(radius));
            bd.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));

            FrameworkElementFactory cp = new FrameworkElementFactory(typeof(ContentPresenter));
            cp.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
            cp.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
            bd.AppendChild(cp);
            tpl.VisualTree = bd;

            Trigger hover = new Trigger();
            hover.Property = UIElement.IsMouseOverProperty;
            hover.Value = true;
            hover.Setters.Add(new Setter(Border.BackgroundProperty, BrushFromHex(hoverHex), "bd"));
            hover.Setters.Add(new Setter(Control.ForegroundProperty, BrushFromHex(hoverFgHex)));
            tpl.Triggers.Add(hover);

            style.Setters.Add(new Setter(Control.TemplateProperty, tpl));
            style.Setters.Add(new Setter(Control.ForegroundProperty, BrushFromHex(fgHex)));
            return style;
        }

        private static SolidColorBrush BrushFromHex(string hex)
        {
            SolidColorBrush b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex);
            if (b.CanFreeze) b.Freeze();
            return b;
        }

        private static void TryDeleteDir(string dir)
        {
            try
            {
                if (Directory.Exists(dir)) Directory.Delete(dir, true);
            }
            catch { }
        }
    }
}
