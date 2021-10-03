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

  let options = {
        \ 'exit_cb': function('s:exit', [a:request]),
        \ 'term_name': '!' . a:request.expanded,
        \ 'term_finish': 'open',
        \ 'curwin': '1',
        \ }
  exe a:request.mods 'split'
  let buf_id = term_start([&shell, &shellcmdflag, a:request.expanded], options)
  let a:request.bufnr = buf_id
  if a:request.background | tabprevious | endif

  let job = term_getjob(buf_id)
  let pid = job_info(job).process
  let a:request.pid = pid
  let s:waiting[pid] = a:request
  call writefile([a:request.pid], a:request.file . '.pid')
  let a:request.handler = 'terminal'

  return 1
endfunction

function! s:exit(request, job, status) abort
  call writefile([a:status], a:request.file . '.complete')

  if has_key(a:request, 'wait') && a:request.wait ==# 'always'
  elseif has_key(a:request, 'wait') && a:request.wait ==# 'never'
    silent exec 'bdelete ' . a:request.bufnr
  elseif has_key(a:request, 'wait') && a:request.wait ==# 'error'
    if a:status == 0
      silent exec 'bdelete ' . a:request.bufnr
    endif
  elseif a:status == 0
    silent exec 'bdelete ' . a:request.bufnr
  endif
  unlet! s:waiting[a:request.pid]
endfunction

function! s:buffer_for_pid(pid) abort
  return filter(term_list(), 'job_info(term_getjob(v:val)).process == ' . a:pid)[0]
endfunction

function! dispatch#terminal#activate(pid) abort
  if index(keys(s:waiting), a:pid) >= 0
    let buf_id = s:buffer_for_pid(a:pid)

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
