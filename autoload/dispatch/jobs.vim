" dispatch.vim jobs strategy

if exists('g:autoloaded_dispatch_jobs')
  finish
endif
let g:autoloaded_dispatch_jobs = 1

let s:waiting = {}

function! dispatch#jobs#handle(request) abort
  if !(has('job') && has('channel') && a:request.action ==# 'make')
    return 0
  endif

  let channel_id = s:start_make_job(a:request)
  if empty(channel_id)
    return 0
  endif

  let s:waiting[channel_id] = a:request
  return 1
endfunction

function! s:start_make_job(request)
  let command = dispatch#prepare_make(a:request)
  let job_options = {
        \ 'close_cb': function('s:CloseCallback'),
        \ 'exit_cb' : function('s:ExitCallback'),
        \ 'out_io'  : 'pipe',
        \ 'err_io'  : 'out',
        \ 'in_io'   : 'null',
        \ 'out_mode': 'nl',
        \ 'err_mode': 'nl'}
  let job = job_start([&shell, &shellcmdflag, command], job_options)
  return s:channel_id(job)
endfunction

function! s:channel_id(job)
  if job_status(a:job) ==# 'fail'
    return ''
  endif

  let channel = job_getchannel(a:job)
  if string(channel) ==# 'channel fail'
    return ''
  endif

  let channel_info = ch_info(channel)
  return string(channel_info.id)
endfun

function! s:ExitCallback(job, status)
  let channel_id = s:channel_id(a:job)
  if has_key(s:waiting, channel_id)
    let request = remove(s:waiting, channel_id)
    call dispatch#complete(request)
  endif
endfun

function! s:CloseCallback(channel)
  " trigger vim calling s:ExitHandler()
  call job_status(ch_getjob(a:channel))
endfun
