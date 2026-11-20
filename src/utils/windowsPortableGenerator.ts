import { DockItem, DockSettings, IconGlyphKey } from '../types/dock';
import { buildZipArchive } from './zipBuilder';

export interface WindowsPresetApp {
  id: string;
  title: string;
  winPath: string;
  winArgs?: string;
  iconKey: IconGlyphKey;
  color: string;
  category: 'system' | 'tools' | 'apps';
}

export const WINDOWS_PRESET_APPS: WindowsPresetApp[] = [
  {
    id: 'win-explorer',
    title: 'Проводник',
    winPath: 'explorer.exe',
    iconKey: 'folder-amber',
    color: '#d97706',
    category: 'system',
  },
  {
    id: 'win-notepad',
    title: 'Блокнот',
    winPath: 'notepad.exe',
    iconKey: 'notes',
    color: '#0284c7',
    category: 'tools',
  },
  {
    id: 'win-calc',
    title: 'Калькулятор',
    winPath: 'calc.exe',
    iconKey: 'calculator',
    color: '#334155',
    category: 'tools',
  },
  {
    id: 'win-terminal',
    title: 'Терминал',
    winPath: 'cmd.exe',
    iconKey: 'terminal',
    color: '#0f172a',
    category: 'tools',
  },
  {
    id: 'win-taskmgr',
    title: 'Диспетчер задач',
    winPath: 'taskmgr.exe',
    iconKey: 'compass',
    color: '#059669',
    category: 'system',
  },
  {
    id: 'win-settings',
    title: 'Параметры Windows',
    winPath: 'ms-settings:',
    iconKey: 'settings',
    color: '#475569',
    category: 'system',
  },
  {
    id: 'win-snip',
    title: 'Ножницы',
    winPath: 'explorer.exe',
    winArgs: 'ms-screenclip:',
    iconKey: 'camera',
    color: '#7c3aed',
    category: 'tools',
  },
  {
    id: 'win-control',
    title: 'Панель управления',
    winPath: 'control.exe',
    iconKey: 'briefcase',
    color: '#2563eb',
    category: 'system',
  },
  {
    id: 'win-vscode',
    title: 'VS Code',
    winPath: '%LOCALAPPDATA%\\Programs\\Microsoft VS Code\\Code.exe',
    iconKey: 'code',
    color: '#0284c7',
    category: 'apps',
  },
  {
    id: 'win-chrome',
    title: 'Google Chrome',
    winPath: 'chrome.exe',
    iconKey: 'globe',
    color: '#0d9488',
    category: 'apps',
  },
  {
    id: 'win-telegram',
    title: 'Telegram',
    winPath: '%APPDATA%\\Telegram Desktop\\Telegram.exe',
    iconKey: 'chat',
    color: '#0284c7',
    category: 'apps',
  },
  {
    id: 'win-recycle',
    title: 'Корзина Windows',
    winPath: 'explorer.exe',
    winArgs: 'shell:RecycleBinFolder',
    iconKey: 'trash',
    color: '#64748b',
    category: 'system',
  },
];

interface PortableStackLink {
  id: string;
  title: string;
  target: string;
  color: string;
  badge: string;
}

interface PortableDockItem {
  id: string;
  type: 'app' | 'url' | 'stack' | 'separator';
  title: string;
  target: string;
  args: string;
  color: string;
  badge: string;
  iconFile?: string;
  stackItems?: PortableStackLink[];
}

function getBadgeChar(item: DockItem): string {
  const clean = item.title.trim();
  if (!clean) return 'A';
  return clean.slice(0, 2).toUpperCase();
}

/**
 * Converts current web AeroDock items into real native Windows executable / URL / Stack targets.
 */
export function buildPortableConfigObject(items: DockItem[], settings: DockSettings) {
  const mapped: PortableDockItem[] = [];

  for (const item of items) {
    if (item.type === 'separator') {
      mapped.push({
        id: item.id,
        type: 'separator',
        title: 'Разделитель',
        target: '',
        args: '',
        color: '#64748b',
        badge: '|',
      });
      continue;
    }

    if (item.type === 'winapp' && item.winPath) {
      mapped.push({
        id: item.id,
        type: 'app',
        title: item.title,
        target: item.winPath,
        args: item.winArgs || '',
        color: item.color,
        badge: getBadgeChar(item),
      });
      continue;
    }

    if (item.type === 'link' && item.url) {
      mapped.push({
        id: item.id,
        type: 'url',
        title: item.title,
        target: item.url,
        args: '',
        color: item.color,
        badge: getBadgeChar(item),
      });
      continue;
    }

    if (item.type === 'stack') {
      mapped.push({
        id: item.id,
        type: 'stack',
        title: item.title,
        target: item.winPath || '',
        args: '',
        color: item.color,
        badge: getBadgeChar(item),
        stackItems: (item.stackItems || []).map((sub) => ({
          id: sub.id,
          title: sub.title,
          target: sub.url,
          color: sub.color,
          badge: sub.title.trim().slice(0, 2).toUpperCase() || 'LN',
        })),
      });
      continue;
    }

    // Map built-in web utilities to authentic built-in Windows apps!
    if (item.appId === 'launcher') {
      mapped.push({
        id: item.id,
        type: 'app',
        title: 'Проводник',
        target: 'explorer.exe',
        args: '',
        color: '#d97706',
        badge: 'ПР',
      });
    } else if (item.appId === 'notes') {
      mapped.push({
        id: item.id,
        type: 'app',
        title: 'Блокнот',
        target: 'notepad.exe',
        args: '',
        color: '#0284c7',
        badge: 'БЛ',
      });
    } else if (item.appId === 'calculator') {
      mapped.push({
        id: item.id,
        type: 'app',
        title: 'Калькулятор',
        target: 'calc.exe',
        args: '',
        color: '#334155',
        badge: 'КЛ',
      });
    } else if (item.appId === 'clock') {
      mapped.push({
        id: item.id,
        type: 'app',
        title: 'Часы Windows',
        target: 'ms-clock:',
        args: '',
        color: '#0f172a',
        badge: 'ЧС',
      });
    } else if (item.appId === 'trash') {
      mapped.push({
        id: item.id,
        type: 'app',
        title: 'Корзина',
        target: 'explorer.exe',
        args: 'shell:RecycleBinFolder',
        color: '#64748b',
        badge: 'КР',
      });
    }
  }

  // Add a live Windows Downloads folder stack by default if user has no folder stack yet
  if (!mapped.some((m) => m.type === 'stack' && m.target)) {
    const trashIdx = mapped.findIndex((m) => m.args === 'shell:RecycleBinFolder');
    const downloadsStack: PortableDockItem = {
      id: 'stack-downloads',
      type: 'stack',
      title: 'Загрузки (Папка)',
      target: '%USERPROFILE%\\Downloads',
      args: '',
      color: '#d97706',
      badge: 'ЗГ',
      stackItems: [],
    };
    if (trashIdx > 0) mapped.splice(trashIdx, 0, downloadsStack);
    else mapped.push(downloadsStack);
  }

  return {
    version: 2,
    portable: true,
    settings: {
      position: settings.position,
      theme: settings.theme,
      iconSize: settings.iconSize,
      zoomScale: settings.zoomScale,
      opacity: settings.opacity,
      edgeOffset: settings.edgeOffset,
      autoHide: settings.autoHide,
      lockIcons: settings.lockIcons,
      topmost: true,
      showLabels: settings.showLabels,
      showRunningIndicators: true,
      displayIndex: 0,
      useAcrylic: false,
      launchWithWindows: false,
      hotkeyEnabled: true,
    },
    items: mapped,
  };
}

/**
 * Generates the complete, zero-install native Windows WPF PowerShell Dock script.
 * Runs on any Windows 10 / Windows 11 PC using built-in .NET PresentationFramework.
 * Supports: transparent floating shelf, smooth zoom on hover, real icon extraction,
 * drag-and-drop .exe/.lnk/folders from Windows Explorer, 4 screen edges, auto-hide,
 * system tray menu, and 100% portable config saved right beside the script.
 */
export function buildWindowsPowerShellDockScript(): string {
  return `<#
  AeroDock Portable for Windows (10 / 11)
  Zero-install native WPF desktop dock inspired by RocketDock.
  All configuration is stored right next to this script in aerodock-config.json.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ScriptDir 'aerodock-config.json'

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
            return $raw | ConvertFrom-Json
        } catch {}
    }
    return [PSCustomObject]@{
        version  = 1
        portable = $true
        settings = [PSCustomObject]@{
            position   = 'bottom'
            theme      = 'aero3d'
            iconSize   = 52
            zoomScale  = 1.45
            opacity    = 84
            edgeOffset = 12
            autoHide   = $false
            topmost    = $true
            showLabels = $true
        }
        items = @(
            [PSCustomObject]@{ id='exp'; type='app'; title='Проводник'; target='explorer.exe'; args=''; color='#d97706'; badge='ПР' },
            [PSCustomObject]@{ id='not'; type='app'; title='Блокнот'; target='notepad.exe'; args=''; color='#0284c7'; badge='БЛ' },
            [PSCustomObject]@{ id='clc'; type='app'; title='Калькулятор'; target='calc.exe'; args=''; color='#334155'; badge='КЛ' },
            [PSCustomObject]@{ id='sep1'; type='separator'; title='Разделитель'; target=''; args=''; color='#64748b'; badge='|' },
            [PSCustomObject]@{ id='trsh'; type='app'; title='Корзина'; target='explorer.exe'; args='shell:RecycleBinFolder'; color='#64748b'; badge='КР' }
        )
    }
}

$Global:Config = Load-Config

function Save-Config {
    try {
        $json = $Global:Config | ConvertTo-Json -Depth 6
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($ConfigPath, $json, $utf8Bom)
    } catch {}
}

function Resolve-TargetPath([string]$rawPath) {
    if ([string]::IsNullOrWhiteSpace($rawPath)) { return '' }
    $expanded = [Environment]::ExpandEnvironmentVariables($rawPath)
    if (Test-Path $expanded) { return $expanded }
    $cmd = Get-Command $expanded -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $expanded
}

function Get-NativeIconSource([string]$targetPath) {
    try {
        $resolved = Resolve-TargetPath $targetPath
        if ($resolved -and (Test-Path $resolved -PathType Leaf)) {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($resolved)
            if ($icon) {
                $bmp = $icon.ToBitmap()
                $hBitmap = $bmp.GetHbitmap()
                $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap(
                    $hBitmap,
                    [IntPtr]::Zero,
                    [System.Windows.Int32Rect]::Empty,
                    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
                )
                $src.Freeze()
                $bmp.Dispose()
                $icon.Dispose()
                return $src
            }
        }
    } catch {}
    return $null
}

function Convert-HexToBrush([string]$hex, [byte]$alpha = 255) {
    try {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $c.A = $alpha
        $b = New-Object System.Windows.Media.SolidColorBrush($c)
        $b.Freeze()
        return $b
    } catch {
        return [System.Windows.Media.Brushes]::SteelBlue
    }
}

function Launch-DockItem($item) {
    try {
        $target = [Environment]::ExpandEnvironmentVariables([string]$item.target)
        $args = [Environment]::ExpandEnvironmentVariables([string]$item.args)
        if ([string]::IsNullOrWhiteSpace($target)) { return }
        if ([string]::IsNullOrWhiteSpace($args)) {
            Start-Process -FilePath $target
        } else {
            Start-Process -FilePath $target -ArgumentList $args
        }
    } catch {
        [System.Windows.MessageBox]::Show("Не удалось запустить: $($item.title)\n$($item.target)", 'AeroDock Portable', 'OK', 'Warning') | Out-Null
    }
}

# Build Main Transparent WPF Window
$Window = New-Object System.Windows.Window
$Window.Title = 'AeroDock Portable'
$Window.WindowStyle = [System.Windows.WindowStyle]::None
$Window.AllowsTransparency = $true
$Window.Background = [System.Windows.Media.Brushes]::Transparent
$Window.ShowInTaskbar = $false
$Window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$Window.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
$Window.AllowDrop = $true
$Window.Topmost = [bool]$Global:Config.settings.topmost

# Outer container with room for hover magnification
$RootGrid = New-Object System.Windows.Controls.Grid
$RootGrid.Margin = New-Object System.Windows.Thickness(26)
$Window.Content = $RootGrid

# Dock Shelf Border
$ShelfBorder = New-Object System.Windows.Controls.Border
$ShelfBorder.CornerRadius = New-Object System.Windows.CornerRadius(18)
$ShelfBorder.BorderThickness = New-Object System.Windows.Thickness(1.2)
$ShelfBorder.Padding = New-Object System.Windows.Thickness(12, 8, 12, 8)

$DropShadow = New-Object System.Windows.Media.Effects.DropShadowEffect
$DropShadow.BlurRadius = 24
$DropShadow.ShadowDepth = 6
$DropShadow.Opacity = 0.55
$DropShadow.Color = [System.Windows.Media.Colors]::Black
$ShelfBorder.Effect = $DropShadow

$IconsPanel = New-Object System.Windows.Controls.StackPanel
$ShelfBorder.Child = $IconsPanel
$RootGrid.Children.Add($ShelfBorder) | Out-Null

# Auto-hide visual state
$Global:IsHiddenStrip = $false

function Apply-Theme {
    $theme = [string]$Global:Config.settings.theme
    $alphaVal = [math]::Max(55, [math]::Min(255, [int]([double]$Global:Config.settings.opacity * 2.55)))

    switch ($theme) {
        'silk' {
            $ShelfBorder.Background = Convert-HexToBrush '#F8FAFC' ([byte]$alphaVal)
            $ShelfBorder.BorderBrush = Convert-HexToBrush '#FFFFFF' 220
        }
        'graphite' {
            $ShelfBorder.Background = Convert-HexToBrush '#0F172A' ([byte]$alphaVal)
            $ShelfBorder.BorderBrush = Convert-HexToBrush '#94A3B8' 85
        }
        'minimal' {
            $ShelfBorder.Background = Convert-HexToBrush '#0F172A' ([byte]([math]::Max(40, $alphaVal * 0.55)))
            $ShelfBorder.BorderBrush = Convert-HexToBrush '#FFFFFF' 45
        }
        'retro' {
            $ShelfBorder.Background = Convert-HexToBrush '#475569' ([byte]$alphaVal)
            $ShelfBorder.BorderBrush = Convert-HexToBrush '#E2E8F0' 150
        }
        default {
            # crystal / aero3d glass tint
            $ShelfBorder.Background = Convert-HexToBrush '#1E293B' ([byte]([math]::Max(75, $alphaVal * 0.78)))
            $ShelfBorder.BorderBrush = Convert-HexToBrush '#FFFFFF' 115
        }
    }
}

function Update-WindowPosition {
    $Window.UpdateLayout()
    $work = [System.Windows.SystemParameters]::WorkArea
    $pos = [string]$Global:Config.settings.position
    $offset = [double]$Global:Config.settings.edgeOffset
    $w = $Window.ActualWidth
    $h = $Window.ActualHeight
    if ($w -le 0) { $w = 400 }
    if ($h -le 0) { $h = 100 }

    $hideShift = 0
    if ($Global:Config.settings.autoHide -and $Global:IsHiddenStrip) {
        $hideShift = [math]::Max(48, ([double]$Global:Config.settings.iconSize + 24))
    }

    switch ($pos) {
        'top' {
            $Window.Left = $work.Left + ($work.Width - $w) / 2
            $Window.Top  = $work.Top + $offset - 18 - $hideShift
        }
        'left' {
            $Window.Left = $work.Left + $offset - 18 - $hideShift
            $Window.Top  = $work.Top + ($work.Height - $h) / 2
        }
        'right' {
            $Window.Left = $work.Right - $w - $offset + 18 + $hideShift
            $Window.Top  = $work.Top + ($work.Height - $h) / 2
        }
        default {
            # bottom
            $Window.Left = $work.Left + ($work.Width - $w) / 2
            $Window.Top  = $work.Bottom - $h - $offset + 18 + $hideShift
        }
    }
}

function Prompt-AddProgram {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Выберите программу (.exe) или ярлык для AeroDock'
    $dlg.Filter = 'Программы и ярлыки (*.exe;*.lnk;*.bat;*.cmd)|*.exe;*.lnk;*.bat;*.cmd|Все файлы (*.*)|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $filePath = $dlg.FileName
        $title = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        $badge = if ($title.Length -ge 2) { $title.Substring(0, 2).ToUpper() } else { 'AP' }
        $newItem = [PSCustomObject]@{
            id     = "win-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            type   = 'app'
            title  = $title
            target = $filePath
            args   = ''
            color  = '#0284c7'
            badge  = $badge
        }
        $list = @($Global:Config.items)
        $list += $newItem
        $Global:Config.items = $list
        Save-Config
        Rebuild-Dock
    }
}

function Prompt-AddFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Выберите папку для добавления на панель AeroDock'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $dirPath = $dlg.SelectedPath
        $title = Split-Path -Leaf $dirPath
        if ([string]::IsNullOrWhiteSpace($title)) { $title = $dirPath }
        $newItem = [PSCustomObject]@{
            id     = "dir-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            type   = 'app'
            title  = $title
            target = $dirPath
            args   = ''
            color  = '#d97706'
            badge  = 'ПД'
        }
        $list = @($Global:Config.items)
        $list += $newItem
        $Global:Config.items = $list
        Save-Config
        Rebuild-Dock
    }
}

function Build-DockContextMenu($itemIndex) {
    $menu = New-Object System.Windows.Controls.ContextMenu

    if ($itemIndex -ge 0) {
        $itm = $Global:Config.items[$itemIndex]
        if ($itm.type -ne 'separator') {
            $mOpen = New-Object System.Windows.Controls.MenuItem
            $mOpen.Header = "Открыть: $($itm.title)"
            $mOpen.Add_Click({ Launch-DockItem $Global:Config.items[$itemIndex] }.GetNewClosure())
            $menu.Items.Add($mOpen) | Out-Null
        }

        if ($itemIndex -gt 0) {
            $mPrev = New-Object System.Windows.Controls.MenuItem
            $mPrev.Header = 'Переместить назад'
            $mPrev.Add_Click({
                $arr = @($Global:Config.items)
                $tmp = $arr[$itemIndex]
                $arr[$itemIndex] = $arr[$itemIndex - 1]
                $arr[$itemIndex - 1] = $tmp
                $Global:Config.items = $arr
                Save-Config
                Rebuild-Dock
            }.GetNewClosure())
            $menu.Items.Add($mPrev) | Out-Null
        }

        if ($itemIndex -lt ($Global:Config.items.Count - 1)) {
            $mNext = New-Object System.Windows.Controls.MenuItem
            $mNext.Header = 'Переместить вперёд'
            $mNext.Add_Click({
                $arr = @($Global:Config.items)
                $tmp = $arr[$itemIndex]
                $arr[$itemIndex] = $arr[$itemIndex + 1]
                $arr[$itemIndex + 1] = $tmp
                $Global:Config.items = $arr
                Save-Config
                Rebuild-Dock
            }.GetNewClosure())
            $menu.Items.Add($mNext) | Out-Null
        }

        $mDel = New-Object System.Windows.Controls.MenuItem
        $mDel.Header = 'Удалить с панели'
        $mDel.Add_Click({
            $arr = New-Object System.Collections.ArrayList
            for ($k = 0; $k -lt $Global:Config.items.Count; $k++) {
                if ($k -ne $itemIndex) { [void]$arr.Add($Global:Config.items[$k]) }
            }
            $Global:Config.items = $arr.ToArray()
            Save-Config
            Rebuild-Dock
        }.GetNewClosure())
        $menu.Items.Add($mDel) | Out-Null
        $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    }

    $mAddExe = New-Object System.Windows.Controls.MenuItem
    $mAddExe.Header = 'Добавить программу (.exe)...'
    $mAddExe.Add_Click({ Prompt-AddProgram })
    $menu.Items.Add($mAddExe) | Out-Null

    $mAddDir = New-Object System.Windows.Controls.MenuItem
    $mAddDir.Header = 'Добавить папку...'
    $mAddDir.Add_Click({ Prompt-AddFolder })
    $menu.Items.Add($mAddDir) | Out-Null

    $mAddSep = New-Object System.Windows.Controls.MenuItem
    $mAddSep.Header = 'Добавить разделитель'
    $mAddSep.Add_Click({
        $sep = [PSCustomObject]@{ id=("sep-"+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()); type='separator'; title='Разделитель'; target=''; args=''; color='#64748b'; badge='|' }
        $list = @($Global:Config.items); $list += $sep
        $Global:Config.items = $list
        Save-Config
        Rebuild-Dock
    })
    $menu.Items.Add($mAddSep) | Out-Null

    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    # Position submenu
    $mPos = New-Object System.Windows.Controls.MenuItem
    $mPos.Header = 'Положение панели'
    foreach ($pair in @(@('bottom','Снизу'), @('top','Сверху'), @('left','Слева'), @('right','Справа'))) {
        $pCode = $pair[0]; $pLabel = $pair[1]
        $sub = New-Object System.Windows.Controls.MenuItem
        $sub.Header = $pLabel
        $sub.IsChecked = ($Global:Config.settings.position -eq $pCode)
        $sub.Add_Click({
            $Global:Config.settings.position = $pCode
            Save-Config
            Rebuild-Dock
        }.GetNewClosure())
        $mPos.Items.Add($sub) | Out-Null
    }
    $menu.Items.Add($mPos) | Out-Null

    $mHide = New-Object System.Windows.Controls.MenuItem
    $mHide.Header = 'Автоскрытие'
    $mHide.IsChecked = [bool]$Global:Config.settings.autoHide
    $mHide.Add_Click({
        $Global:Config.settings.autoHide = -not [bool]$Global:Config.settings.autoHide
        $Global:IsHiddenStrip = $false
        Save-Config
        Update-WindowPosition
    })
    $menu.Items.Add($mHide) | Out-Null

    $mTop = New-Object System.Windows.Controls.MenuItem
    $mTop.Header = 'Поверх всех окон'
    $mTop.IsChecked = [bool]$Global:Config.settings.topmost
    $mTop.Add_Click({
        $Global:Config.settings.topmost = -not [bool]$Global:Config.settings.topmost
        $Window.Topmost = [bool]$Global:Config.settings.topmost
        Save-Config
    })
    $menu.Items.Add($mTop) | Out-Null

    $mFolder = New-Object System.Windows.Controls.MenuItem
    $mFolder.Header = 'Открыть папку конфигурации'
    $mFolder.Add_Click({ Start-Process explorer.exe -ArgumentList $ScriptDir })
    $menu.Items.Add($mFolder) | Out-Null

    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    $mExit = New-Object System.Windows.Controls.MenuItem
    $mExit.Header = 'Выход из AeroDock'
    $mExit.Add_Click({ $Window.Close() })
    $menu.Items.Add($mExit) | Out-Null

    return $menu
}

function Rebuild-Dock {
    Apply-Theme
    $IconsPanel.Children.Clear()

    $pos = [string]$Global:Config.settings.position
    $isHorizontal = ($pos -eq 'bottom' -or $pos -eq 'top')
    $IconsPanel.Orientation = if ($isHorizontal) {
        [System.Windows.Controls.Orientation]::Horizontal
    } else {
        [System.Windows.Controls.Orientation]::Vertical
    }

    $iconSize = [double]$Global:Config.settings.iconSize
    if ($iconSize -lt 32) { $iconSize = 48 }
    $zoom = [double]$Global:Config.settings.zoomScale
    if ($zoom -lt 1.0) { $zoom = 1.35 }

    $ShelfBorder.ContextMenu = Build-DockContextMenu -1

    for ($i = 0; $i -lt $Global:Config.items.Count; $i++) {
        $idx = $i
        $item = $Global:Config.items[$idx]

        if ($item.type -eq 'separator') {
            $sep = New-Object System.Windows.Controls.Border
            $sep.Background = Convert-HexToBrush '#FFFFFF' 90
            $sep.CornerRadius = New-Object System.Windows.CornerRadius(2)
            if ($isHorizontal) {
                $sep.Width = 2
                $sep.Height = [math]::Round($iconSize * 0.65)
                $sep.Margin = New-Object System.Windows.Thickness(6, 4, 6, 4)
            } else {
                $sep.Height = 2
                $sep.Width = [math]::Round($iconSize * 0.65)
                $sep.Margin = New-Object System.Windows.Thickness(4, 6, 4, 6)
            }
            $sep.ContextMenu = Build-DockContextMenu $idx
            $IconsPanel.Children.Add($sep) | Out-Null
            continue
        }

        $tile = New-Object System.Windows.Controls.Border
        $tile.Width = $iconSize
        $tile.Height = $iconSize
        $tile.Margin = New-Object System.Windows.Thickness(5)
        $tile.CornerRadius = New-Object System.Windows.CornerRadius([math]::Round($iconSize * 0.24))
        $tile.Cursor = [System.Windows.Input.Cursors]::Hand
        $tile.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)

        $tg = New-Object System.Windows.Media.TransformGroup
        $scaleT = New-Object System.Windows.Media.ScaleTransform(1.0, 1.0)
        $transT = New-Object System.Windows.Media.TranslateTransform(0, 0)
        $tg.Children.Add($scaleT) | Out-Null
        $tg.Children.Add($transT) | Out-Null
        $tile.RenderTransform = $tg

        $nativeIcon = if ($item.type -eq 'app') { Get-NativeIconSource $item.target } else { $null }
        if ($nativeIcon) {
            $tile.Background = Convert-HexToBrush '#0F172A' 70
            $tile.BorderBrush = Convert-HexToBrush '#FFFFFF' 60
            $tile.BorderThickness = New-Object System.Windows.Thickness(1)
            $img = New-Object System.Windows.Controls.Image
            $img.Source = $nativeIcon
            $img.Margin = New-Object System.Windows.Thickness(5)
            $img.Stretch = [System.Windows.Media.Stretch]::Uniform
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($img, [System.Windows.Media.BitmapScalingMode]::HighQuality)
            $tile.Child = $img
        } else {
            $tile.Background = Convert-HexToBrush ([string]$item.color) 240
            $tile.BorderBrush = Convert-HexToBrush '#FFFFFF' 90
            $tile.BorderThickness = New-Object System.Windows.Thickness(1)
            $txt = New-Object System.Windows.Controls.TextBlock
            $txt.Text = if ($item.badge) { [string]$item.badge } else { 'AD' }
            $txt.Foreground = [System.Windows.Media.Brushes]::White
            $txt.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
            $txt.FontWeight = [System.Windows.FontWeights]::SemiBold
            $txt.FontSize = [math]::Max(13, [math]::Round($iconSize * 0.34))
            $txt.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $tile.Child = $txt
        }

        if ($Global:Config.settings.showLabels) {
            $tile.ToolTip = [string]$item.title
        }

        $tile.ContextMenu = Build-DockContextMenu $idx

        # Smooth RocketDock hover zoom & lift
        $liftY = if ($pos -eq 'bottom') { -10.0 } elseif ($pos -eq 'top') { 10.0 } else { 0.0 }
        $liftX = if ($pos -eq 'left') { 10.0 } elseif ($pos -eq 'right') { -10.0 } else { 0.0 }

        $tile.Add_MouseEnter({
            $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(140))
            $animS = New-Object System.Windows.Media.Animation.DoubleAnimation($zoom, $dur)
            $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animS)
            $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animS)
            if ($liftY -ne 0) {
                $animY = New-Object System.Windows.Media.Animation.DoubleAnimation($liftY, $dur)
                $transT.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animY)
            }
            if ($liftX -ne 0) {
                $animX = New-Object System.Windows.Media.Animation.DoubleAnimation($liftX, $dur)
                $transT.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animX)
            }
        }.GetNewClosure())

        $tile.Add_MouseLeave({
            $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(160))
            $animS = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, $dur)
            $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animS)
            $scaleT.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animS)
            $animZ = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, $dur)
            $transT.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animZ)
            $transT.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animZ)
        }.GetNewClosure())

        $tile.Add_MouseLeftButtonUp({
            Launch-DockItem $item
        }.GetNewClosure())

        $IconsPanel.Children.Add($tile) | Out-Null
    }

    Update-WindowPosition
}

# Real Windows Drag-and-Drop onto the Dock!
$Window.Add_Drop({
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
        $list = @($Global:Config.items)
        foreach ($f in $files) {
            $title = [System.IO.Path]::GetFileNameWithoutExtension($f)
            if ([string]::IsNullOrWhiteSpace($title)) { $title = Split-Path -Leaf $f }
            $badge = if ($title.Length -ge 2) { $title.Substring(0, 2).ToUpper() } else { 'EX' }
            $list += [PSCustomObject]@{
                id     = "drop-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + "-" + (Get-Random -Max 999)
                type   = 'app'
                title  = $title
                target = $f
                args   = ''
                color  = '#0284c7'
                badge  = $badge
            }
        }
        $Global:Config.items = $list
        Save-Config
        Rebuild-Dock
    }
})

# Auto-hide hover reveal
$Window.Add_MouseEnter({
    if ($Global:Config.settings.autoHide -and $Global:IsHiddenStrip) {
        $Global:IsHiddenStrip = $false
        Update-WindowPosition
    }
})

$Window.Add_MouseLeave({
    if ($Global:Config.settings.autoHide -and -not $Global:IsHiddenStrip) {
        $Global:IsHiddenStrip = $true
        Update-WindowPosition
    }
})

# System Tray Icon for quick access & clean exit
$TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$TrayIcon.Icon = [System.Drawing.SystemIcons]::Application
$TrayIcon.Text = 'AeroDock Portable'
$TrayIcon.Visible = $true

$TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$tShow = $TrayMenu.Items.Add('Показать AeroDock')
$tShow.Add_Click({
    $Global:IsHiddenStrip = $false
    Update-WindowPosition
    $Window.Activate() | Out-Null
})
$tAdd = $TrayMenu.Items.Add('Добавить программу (.exe)...')
$tAdd.Add_Click({ Prompt-AddProgram })
$tDir = $TrayMenu.Items.Add('Открыть папку AeroDock')
$tDir.Add_Click({ Start-Process explorer.exe -ArgumentList $ScriptDir })
$tExit = $TrayMenu.Items.Add('Выход')
$tExit.Add_Click({ $Window.Close() })
$TrayIcon.ContextMenuStrip = $TrayMenu

$Window.Add_Loaded({
    Rebuild-Dock
    if ($Global:Config.settings.autoHide) {
        $Global:IsHiddenStrip = $true
        Update-WindowPosition
    }
})

$Window.Add_Closed({
    $TrayIcon.Visible = $false
    $TrayIcon.Dispose()
})

[void]$Window.ShowDialog()
`;
}

export function buildSilentVbsLauncher(): string {
  return `Set fso = CreateObject("Scripting.FileSystemObject")\r\n` +
    `dir = fso.GetParentFolderName(WScript.ScriptFullName)\r\n` +
    `psFile = dir & "\\AeroDock.ps1"\r\n` +
    `Set shell = CreateObject("WScript.Shell")\r\n` +
    `shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & psFile & """", 0, False\r\n`;
}

export function buildBatchLauncher(): string {
  return `@echo off\r\n` +
    `chcp 65001 >nul\r\n` +
    `start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0AeroDock.ps1"\r\n`;
}

export function buildReadmeRu(): string {
  return `=======================================================\r\n` +
    `  AeroDock Portable для Windows 10 / 11\r\n` +
    `=======================================================\r\n\r\n` +
    `Портативная версия панели запуска в стиле RocketDock.\r\n` +
    `Не требует установки, прав администратора и не пишет в реестр.\r\n` +
    `Можно хранить в любой папке или запускать прямо с USB-флешки.\r\n\r\n` +
    `КАК ЗАПУСТИТЬ:\r\n` +
    `1. Распакуйте весь архив в любую папку (например, D:\\AeroDock).\r\n` +
    `2. Запустите файл «AeroDock-Start.vbs» (без мигающего чёрного окна)\r\n` +
    `   или «AeroDock-Start.bat».\r\n\r\n` +
    `ВОЗМОЖНОСТИ ПОРТАТИВНОЙ ВЕРСИИ:\r\n` +
    `• Перетаскивайте любые .exe, ярлыки .lnk и папки из Проводника прямо\r\n` +
    `  на панель — они мгновенно закрепятся с родными значками Windows.\r\n` +
    `• Нажмите правой кнопкой мыши по панели или значку для добавления\r\n` +
    `  программ, папок, разделителей, смены края экрана и автоскрытия.\r\n` +
    `• В области уведомлений (трее) рядом с часами есть значок AeroDock\r\n` +
    `  для быстрого вызова или выхода.\r\n` +
    `• Все настройки сохраняются рядом в файле aerodock-config.json.\r\n\r\n` +
    `ДОБАВЛЕНИЕ В АВТОЗАГРУЗКУ WINDOWS (по желанию):\r\n` +
    `Нажмите Win + R, введите shell:startup и поместите туда ярлык\r\n` +
    `на файл AeroDock-Start.vbs.\r\n`;
}

export function downloadWindowsPortableZip(items: DockItem[], settings: DockSettings) {
  const configObj = buildPortableConfigObject(items, settings);
  const configJson = JSON.stringify(configObj, null, 2);

  const blob = buildZipArchive([
    {
      name: 'AeroDock-Portable/AeroDock-Start.vbs',
      content: buildSilentVbsLauncher(),
    },
    {
      name: 'AeroDock-Portable/AeroDock-Start.bat',
      content: buildBatchLauncher(),
    },
    {
      name: 'AeroDock-Portable/AeroDock.ps1',
      content: buildWindowsPowerShellDockScript(),
      withUtf8Bom: true,
    },
    {
      name: 'AeroDock-Portable/aerodock-config.json',
      content: configJson,
      withUtf8Bom: true,
    },
    {
      name: 'AeroDock-Portable/README-RU.txt',
      content: buildReadmeRu(),
      withUtf8Bom: true,
    },
  ]);

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'AeroDock-Windows-Portable.zip';
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1500);
}

export function downloadPortableConfigOnly(items: DockItem[], settings: DockSettings) {
  const configObj = buildPortableConfigObject(items, settings);
  const json = '\uFEFF' + JSON.stringify(configObj, null, 2);
  const blob = new Blob([json], { type: 'application/json;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'aerodock-config.json';
  a.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1500);
}
