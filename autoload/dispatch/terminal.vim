" dispatch.vim terminal strategy

if exists('g:autoloaded_dispatch_terminal')
  finish
endif
let g:autoloaded_dispatch_terminal = 1

if !exists('s:waiting')
  let s:waiting = {}
endif

function! dispatch#terminal#handle(request) abort
  if !get(g:, 'dispatch_experimental', 1)
    return 0
  endif
  if !has('terminal') || a:request.action !=# 'start'
    return 0
  endif

  call dispatch#autowrite()

  let options = {
        \ 'exit_cb': function('s:exit'),
        \ 'hidden': 1,
        \ 'term_name': a:request.title,
        \ 'term_finish': (a:request.background ? 'open' : 'close'),
        \ }
  let buf_id = term_start([&shell, &shellcmdflag, a:request.expanded], options)
  silent exec 'tab sbuffer' . buf_id
  if a:request.background | tabprevious | endif

  let job = term_getjob(buf_id)
  let a:request.pid = job_info(job).process
  let pid = job_info(job).process
  let s:waiting[pid] = a:request
  call writefile([a:request.pid], a:request.file . '.pid')
  let a:request.handler = 'terminal'

  return 1
endfunction

function! s:exit(job, status) abort
  let pid = job_info(a:job).process
  let request = s:waiting[pid]
  call writefile([a:status], request.file . '.complete')
  unlet! s:waiting[pid]
endfunction

function! dispatch#terminal#activate(pid) abort
  if index(keys(s:waiting), a:pid) >= 0
    let buf_id = filter(term_list(), 'job_info(term_getjob(v:val)).process == ' . a:pid)[0]

    if buf_id
      let pre = &switchbuf

      try
        let &switchbuf = 'useopen,usetab'
        silent exec 'tab sbuffer' . buf_id
      finally
        let &switchbuf = pre
      endtry
      return 1
    else
      return 0
    endif
  endif

  return 0
endfunction
