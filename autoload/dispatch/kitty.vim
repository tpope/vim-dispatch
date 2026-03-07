" dispatch.vim kitty strategy
"
" This handler requires you to enable kitty's remote control feature.
" See https://sw.kovidgoyal.net/kitty/remote-control/

if exists('g:autoloaded_dispatch_kitty')
  finish
endif
let g:autoloaded_dispatch_kitty = 1

let s:waiting = {}

" -----------------------------------------------------------------------------
" Public handler interface

function! dispatch#kitty#handle(request) abort
  if empty($KITTY_LISTEN_ON) || !executable('kitten')
    return 0
  endif

  if a:request.action ==# 'make'
    return s:make(a:request)
  elseif a:request.action ==# 'start'
    return s:start(a:request)
  endif
endfunction

function! dispatch#kitty#activate(pid) abort
  call system('kitten @ focus-window --match pid:' . a:pid)
  return !v:shell_error
endfunction

" -----------------------------------------------------------------------------
" Private implementation of the "kitty" handler

" Handle: :Start, :Spawn
function! s:start(request) abort
  let cmd = s:kitty_launch_cmd('tab', a:request, dispatch#prepare_start(a:request))

  call system(cmd)
  return 1
endfunction

" Handle: :Dispatch, :Make
function! s:make(request) abort
  let qf_height = get(g:, 'dispatch_quickfix_height', 10)
  if get(a:request, 'background', 0) || (qf_height <= 0 && dispatch#has_callback())
    let type = 'tab'
  else
    let type = 'window'
  endif

  let cmd_with_capturing = a:request.expanded .
                      \ '; echo ' . dispatch#status_var() . ' > ' . a:request.file . '.complete' .
                      \ '; kitten @ get-text --match=id:$KITTY_WINDOW_ID --ansi=no --extent all > ' . a:request.file

  let cmd = s:kitty_launch_cmd(type, a:request, dispatch#prepare_start(a:request, cmd_with_capturing, 'make'))
  let output = system(cmd)
  let window_id = matchstr(output, '\d\+')

  if !empty(window_id)
    let s:waiting[window_id] = a:request
    return 1
  endif
endfunction

" https://sw.kovidgoyal.net/kitty/launch/
function! s:kitty_launch_cmd(type, request, command) abort
  let cmd = 'kitten @ launch'
  let cmd .= ' --cwd=' . shellescape(a:request.directory)
  let cmd .= ' --copy-env --env SHLVL --env PWD --env VIM --env VIMRUNTIME --env MYVIMRC --env NVIM_LOG_FILE'

  if a:request.background || a:request.action ==# 'make'
    let cmd .= ' --keep-focus'
  endif

  if a:type ==# 'tab'
    let cmd .= ' --type=tab --tab-title=' . shellescape(a:request.title)
  else
    let cmd .= ' --type=window --location=hsplit --window-title=' . shellescape(a:request.title)
    let bias = get(g:, 'dispatch_kitty_bias', 0)
    if bias != 0
      let cmd .= ' --bias=' . bias
    endif
  endif

  return cmd . ' sh -c ' . shellescape(a:command)
endfunction

" Section: Without callback - polling

function! s:poll() abort
  if empty(s:waiting)
    return
  endif

  for [window_id, request] in items(s:waiting)
    if !s:kitty_win_exists(window_id)
      call remove(s:waiting, window_id)
      call dispatch#complete(request)
    endif
  endfor
endfunction

function! s:kitty_win_exists(wid) abort
  call system('kitten @ ls --match id:' . a:wid)
  return !v:shell_error
endfunction

augroup dispatch_kitty
  autocmd!
  autocmd VimResized * nested if !dispatch#has_callback() | call s:poll() | endif
augroup END
