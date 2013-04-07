" dispatch.vim tmux strategy

if exists('g:autoloaded_dispatch_tmux')
  finish
endif
let g:autoloaded_dispatch_tmux = 1

let s:waiting = {}
let s:make_pane = tempname()

function! dispatch#tmux#handle(request) abort
  let session = get(g:, 'tmux_session', '')
  if empty($TMUX) && empty(session) || !executable('tmux')
    return 0
  endif
  if !empty(system('tmux has-session -t '.shellescape(session))[0:-2])
    return ''
  endif

  if a:request.action ==# 'make'
    return dispatch#tmux#make(a:request)
  elseif a:request.action ==# 'start'
    let command = 'tmux new-window -t '.shellescape(session.':')
    let command .= ' -n '.shellescape(a:request.title)
    if a:request.background
      let command .= ' -d'
    endif
    let command .= ' ' . shellescape('exec ' . dispatch#isolate(a:request.expanded))
    call system(command)
    return 1
  endif
endfunction

function! dispatch#tmux#make(request) abort
  let session = get(g:, 'tmux_session', '')
  let script = dispatch#isolate(dispatch#prepare_make(a:request, a:request.expanded))

  let title = shellescape(get(a:request, 'compiler', 'make'))
  if get(a:request, 'background', 0)
    let cmd = 'new-window -d -n '.title
  elseif has('gui_running') || empty($TMUX) || (!empty(session) && session !=# system('tmux display-message -p "#S"')[0:-2])
    let cmd = 'new-window -n '.title
  else
    let cmd = 'split-window -l 10 -d'
  endif

  let cmd .= ' ' . dispatch#shellescape('-P', '-t', session.':', dispatch#set_title(a:request) . '; exec ' . script)

  let filter = 'sed'
  let uname = system('uname')[0:-2]
  if uname ==# 'Darwin'
    let filter .= ' -l'
  elseif uname ==# 'Linux'
    let filter .= ' -u'
  endif
  let filter .= " -e \"s/\r//g\" -e \"s/\e[[0-9;]*m//g\" > ".a:request.file
  call system('tmux ' . cmd . '|tee ' . s:make_pane . '|xargs -I {} tmux pipe-pane -t {} '.shellescape(filter))

  let pane = get(readfile(s:make_pane, '', 1), 0, '')
  return s:record(pane, a:request)
endfunction

function! s:record(pane, request)
  if a:pane =~# '\.\d\+$'
    let [window, index] = split(a:pane, '\.\%(\d\+$\)\@=')
    let out = system('tmux list-panes -F "#P #{pane_id}" -t '.shellescape(window))
    let id = matchstr("\n".out, '\n'.index.' \+\zs%\d\+')
  else
    let id = system('tmux list-panes -F "#{pane_id}" -t '.shellescape(a:pane))[0:-2]
  endif

  if empty(id)
    return 0
  endif
  let s:waiting[id] = a:request
  return 1

endfunction

function! dispatch#tmux#poll() abort
  if empty(s:waiting)
    return
  endif
  let panes = split(system('tmux list-panes -a -F "#{pane_id}"'), "\n")
  for [pane, request] in items(s:waiting)
    if index(panes, pane) < 0
      call remove(s:waiting, pane)
      call dispatch#complete(request)
    endif
  endfor
endfunction

augroup dispatch_tmux
  autocmd!
  autocmd VimResized * if !has('gui_running') | call dispatch#tmux#poll() | endif
augroup END
