" dispatch.vim vimproc strategy

if exists('g:autoloaded_dispatch_vimproc')
  finish
endif
let g:autoloaded_dispatch_vimproc = 1

function! dispatch#vimproc#handle(request) abort
  if !exists('g:loaded_vimproc')
    return 0
  endif

  if a:request.action ==# 'make'
    let command = dispatch#prepare_make(a:request)
  elseif a:request.action ==# 'start'
    let command = dispatch#prepare_start(a:request)
  endif

  if &shellredir =~# '%s'
    let redir = printf(&shellredir, '/dev/null')
  else
    let redir = &shellredir . ' ' . '/dev/null'
  endif

  let process = vimproc#popen2(&shell.' '.&shellcmdflag.' '.shellescape(command).redir.' &')
  let [cond, status] = process.waitpid()

  return !status
endfunction

function! dispatch#vimproc#activate(pid) abort
  return 0
endfunction
