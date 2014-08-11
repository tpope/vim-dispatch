" dispatch.vim GNU Screen strategy

if exists('g:autoloaded_dispatch_screen')
  finish
endif
let g:autoloaded_dispatch_screen = 1

let s:waiting = {}

function! dispatch#screen#handle(request) abort
  if empty($STY) || !executable('screen')
    return 0
  endif
  if a:request.action ==# 'make'
    if !get(a:request, 'background', 0) && empty(v:servername) && !empty(s:waiting)
	  return 0
    endif
    return dispatch#screen#spawn(dispatch#prepare_make(a:request), a:request)
  elseif a:request.action ==# 'start'
    return dispatch#screen#spawn(dispatch#prepare_start(a:request), a:request)
  endif
endfunction

function! dispatch#screen#spawn(command, request) abort
  let teardown = 'screen -X eval "focus bottom" "remove"'
  if a:request.background
    let teardown = ''
  endif
  let command = 'screen -ln -fn -t '.dispatch#shellescape(a:request.title)
        \ . ' ' . &shell . ' ' . &shellcmdflag . ' '
        \ . shellescape('exec ' . dispatch#isolate(['STY', 'WINDOW'],
        \ dispatch#set_title(a:request), a:command, teardown))

  if a:request.background
    let command = command
  else
    let command = 'screen -X eval "split" "focus down" "resize 10" "' . substitute(command, '"', '\"', '') . '" "focus up"'
  endif

  call system(command)

  if !a:request.background
    let s:waiting = a:request
  endif

  return 1
endfunction

function! dispatch#screen#activate(pid) abort
  let out = system('ps ewww -p '.a:pid)
  if empty($STY) || stridx(out, 'STY='.$STY) < 0
    return 0
  endif
  let window = matchstr(out, 'WINDOW=\zs\d\+')
  if !empty(window)
    silent execute '!screen -X select '.window
    return !v:shell_error
  endif
endfunction

function! dispatch#screen#poll() abort
  if empty(s:waiting)
    return
  endif

  let pid = dispatch#pid(s:waiting)
  if !pid
    let request = s:waiting
    let s:waiting = {}
    call dispatch#complete(request)
  endif
endfunction

augroup dispatch_screen
  autocmd!
  autocmd VimResized * if !has('gui_running') | call dispatch#screen#poll() | endif
augroup END
