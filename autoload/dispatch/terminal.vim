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
  let has_terminal = (has('terminal') || has('nvim'))
  if !has_terminal || a:request.action !=# 'start'
    return 0
  endif

  let a:request.handler = 'terminal'

  if has('nvim')
    exe a:request.mods 'new'
    let options = {
          \ 'on_exit': function('s:exit', [a:request]),
          \ }
    let job = termopen(a:request.expanded, options)
    let a:request.bufnr = bufnr('')
    let a:request.pid = jobpid(job)
    startinsert
  else
    exe a:request.mods 'split'
    let options = {
          \ 'exit_cb': function('s:exit', [a:request]),
          \ 'term_name': '!' . a:request.expanded,
          \ 'term_finish': 'open',
          \ 'curwin': 1,
          \ }
    let a:request.bufnr = term_start([&shell, &shellcmdflag, a:request.expanded], options)
    let job = term_getjob(a:request.bufnr)
    let a:request.pid = job_info(job).process
  endif

  let s:waiting[a:request.pid] = a:request
  call writefile([a:request.pid], a:request.file . '.pid')

  return 1
endfunction

function! s:exit(request, job, status, ...) abort
  call writefile([a:status], a:request.file . '.complete')

  let wait = get(a:request, 'wait', 'error')
  if wait ==# 'never' || (wait !=# 'always' && a:status == 0)
    silent exec 'bdelete! ' . a:request.bufnr
  endif

  unlet! s:waiting[a:request.pid]
endfunction

function! dispatch#terminal#activate(pid) abort
  if has_key(s:waiting, a:pid)
    let request = s:waiting[a:pid]
    let pre = &switchbuf

    try
      let &switchbuf = 'useopen,usetab'
      silent exe a:request.mods 'sbuffer' a:request.bufnr
    finally
      let &switchbuf = pre
    endtry
    return 1
  endif

  return 0
endfunction
