" dispatch.vim job strategy

if exists('g:autoloaded_dispatch_job')
  finish
endif
let g:autoloaded_dispatch_job = 1

if !exists('s:waiting')
  let s:waiting = {}
endif

function! dispatch#job#handle(request) abort
  if !has('job') || a:request.action !=# 'make'
    return 0
  endif
  call writefile([], a:request.file)
  let job = job_start([&shell, &shellcmdflag, a:request.expanded], {
        \ 'in_io': 'null',
        \ 'out_mode': 'nl',
        \ 'err_mode': 'nl',
        \ 'callback': function('s:output'),
        \ 'exit_cb': function('s:exit'),
        \ })
  let a:request.pid = job_info(job).process
  let ch_id = ch_info(job_info(job).channel).id
  let s:waiting[ch_id] = a:request
  call writefile([a:request.pid], a:request.file . '.pid')
  let a:request.handler = 'job'
  return 2
endfunction

function! s:exit(job, status) abort
  let ch_id = ch_info(job_info(a:job).channel).id
  let request = s:waiting[ch_id]
  call writefile([a:status], request.file . '.complete')
  " unlet! s:waiting[ch_id]
  call DispatchComplete(request.id)
endfunction

function! s:output(ch, output) abort
  let ch_id = ch_info(a:ch).id
  let request = s:waiting[ch_id]
  call writefile([a:output], request.file, 'a')

  if dispatch#request(getqflist({'all': 1}).title) isnot# request
    return
  endif

  let efm = &l:efm
  let makeprg = &l:makeprg
  let compiler = get(b:, 'current_compiler', '')
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : 'cd'
  let dir = getcwd()
  let modelines = &modelines
  try
    let &modelines = 0
    let b:current_compiler = get(request, 'complier', '')
    if empty(b:current_compiler)
      unlet! b:current_compiler
    endif
    exe cd fnameescape(request.directory)
    let &l:efm = request.format
    let &l:makeprg = request.command
    caddexpr a:output
  finally
    let &modelines = modelines
    exe cd fnameescape(dir)
    let &l:efm = efm
    let &l:makeprg = makeprg
    if empty(compiler)
      unlet! b:current_compiler
    else
      let b:current_compiler = compiler
    endif
  endtry
  cbottom
endfunction

function! dispatch#job#activate(pid) abort
  return 0
endfunction
