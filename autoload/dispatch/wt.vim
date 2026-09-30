" dispatch.vim Windows Terminal strategy

if exists('g:autoloaded_dispatch_wt')
  finish
endif
let g:autoloaded_dispatch_wt = 1

if !exists('s:waiting')
  let s:waiting = {}
endif

function! dispatch#wt#handle(request) abort
  if !has('win32') || has('gui_running') || empty($WT_SESSION) || !executable('wt')
    return 0
  endif
  if !exists('*job_start') && !exists('*jobstart') || !exists('*timer_start')
    return 0
  endif
  if a:request.action ==# 'make'
    return dispatch#wt#spawn(a:request, 1, 0)
  elseif a:request.action ==# 'start'
    return dispatch#wt#spawn(a:request, 0, !a:request.background)
  endif
endfunction

function! s:ps_quote(str) abort
  return "'" . substitute(a:str, "'", "''", 'g') . "'"
endfunction

" Quote a single argument per the CommandLineToArgvW rules.
function! s:argv_quote(str) abort
  let str = substitute(a:str, '\(\\*\)"', '\1\1\\"', 'g')
  let str = substitute(str, '\(\\\+\)$', '\1\1', '')
  return '"' . str . '"'
endfunction

" Arguments for $env:ComSpec that run the request under 'shell'.
function! s:cmd_arguments(request, capture) abort
  if &shell =~? '\%(^\|[\\/]\)cmd\%(\.exe\)\=$'
    let command = a:request.expanded
  else
    let command = &shell . ' ' . &shellcmdflag . ' ' . s:argv_quote(a:request.expanded)
  endif
  if a:capture
    let command = '(' . command . ') 2>&1'
  endif
  return '/d /s /c "' . command . '"'
endfunction

function! s:script(request, capture) abort
  let file = a:request.file
  let lines = [
        \ '$PSNativeCommandArgumentPassing = ''Legacy''',
        \ 'Set-Location -LiteralPath ' . s:ps_quote(getcwd()),
        \ '$Host.UI.RawUI.WindowTitle = ' . s:ps_quote(a:request.title),
        \ '$status = -1',
        \ 'try {',
        \ '  $psi = New-Object System.Diagnostics.ProcessStartInfo',
        \ '  $psi.FileName = $env:ComSpec',
        \ '  $psi.Arguments = ' . s:ps_quote(s:cmd_arguments(a:request, a:capture)),
        \ '  $psi.WorkingDirectory = ' . s:ps_quote(getcwd()),
        \ '  $psi.UseShellExecute = $false',
        \ ]
  if a:capture
    let lines += [
          \ '  $enc = [Console]::OutputEncoding',
          \ '  if ($enc.CodePage -eq 65001) { $enc = New-Object System.Text.UTF8Encoding $false }',
          \ '  $psi.RedirectStandardOutput = $true',
          \ '  $psi.StandardOutputEncoding = $enc',
          \ ]
  endif
  let lines += [
        \ '  $p = [System.Diagnostics.Process]::Start($psi)',
        \ '  [IO.File]::WriteAllText(' . s:ps_quote(file . '.pid') . ', "$($p.Id)")',
        \ ]
  if a:capture
    let lines += [
          \ '  $out = New-Object System.IO.StreamWriter(' . s:ps_quote(file) . ', $false, $enc)',
          \ '  try {',
          \ '    while ($null -ne ($line = $p.StandardOutput.ReadLine())) {',
          \ '      [Console]::WriteLine($line)',
          \ '      $out.WriteLine($line)',
          \ '    }',
          \ '  } finally { $out.Close() }',
          \ ]
  endif
  let lines += [
        \ '  $p.WaitForExit()',
        \ '  $status = $p.ExitCode',
        \ ]
  if !a:capture
    let wait = get(a:request, 'wait', 'error')
    if wait ==# 'always'
      let pause = '$true'
    elseif wait ==# 'never'
      let pause = '$false'
    else
      " -1073741510 is STATUS_CONTROL_C_EXIT
      let pause = '$status -ne 0 -and $status -ne -1073741510'
    endif
    let lines += [
          \ '  if (' . pause . ') {',
          \ '    Write-Host ''--- Press ENTER to continue ---'' -ForegroundColor White',
          \ '    [void][Console]::ReadLine()',
          \ '  }',
          \ ]
  endif
  let lines += [
        \ '} finally {',
        \ '  [IO.File]::WriteAllText(' . s:ps_quote(file . '.complete') . ', "$status")',
        \ '}',
        \ 'exit 0',
        \ ]
  return lines
endfunction

function! dispatch#wt#spawn(request, capture, focus) abort
  let script = a:request.file . '.ps1'
  let lines = s:script(a:request, a:capture)
  if &encoding ==# 'utf-8'
    " Windows PowerShell only reads a script as UTF-8 given a BOM.
    let lines[0] = "\xef\xbb\xbf" . lines[0]
  endif
  call writefile(lines, script)

  let height = get(g:, 'dispatch_wt_height', get(g:, 'dispatch_quickfix_height', 10))
  let height = height < 0 ? -height : height
  let size = printf('%.2f', min([max([height * 1.0 / max([&lines, 1]), 0.05]), 0.9]))
  let shell = executable('pwsh') ? 'pwsh' : 'powershell'
  let cmd = ['wt', '-w', '0', 'split-pane', '-H', '-s', size,
        \ '--title', a:request.title,
        \ shell, '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script]
  if !a:focus
    let cmd += [';', 'move-focus', 'up']
  endif
  if exists('*job_start')
    call job_start(cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  else
    call jobstart(cmd)
  endif

  let a:request.handler = 'wt'
  let s:waiting[a:request.file] = a:request
  if !exists('s:timer')
    let s:timer = timer_start(250, function('s:poll'), {'repeat': -1})
  endif
  return 1
endfunction

function! s:poll(timer) abort
  for [file, request] in items(s:waiting)
    if filereadable(file . '.complete')
      call remove(s:waiting, file)
      if request.action ==# 'make'
        call dispatch#complete(request)
      endif
    endif
  endfor
  if empty(s:waiting)
    call timer_stop(a:timer)
    unlet! s:timer
  endif
endfunction

function! dispatch#wt#kill(pid, force) abort
  call system('taskkill /T ' . (a:force ? '/F ' : '') . '/PID ' . a:pid)
endfunction
