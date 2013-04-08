" autoload/dispatch.vim
if exists('g:autoloaded_dispatch')
  finish
endif

let g:autoloaded_dispatch = 1

" Utility {{{1

function! dispatch#uniq(list) abort
  let i = 0
  let seen = {}
  while i < len(a:list)
    if (a:list[i] ==# '' && exists('empty')) || has_key(seen,a:list[i])
      call remove(a:list,i)
    elseif a:list[i] ==# ''
      let i += 1
      let empty = 1
    else
      let seen[a:list[i]] = 1
      let i += 1
    endif
  endwhile
  return a:list
endfunction

function! dispatch#shellescape(...) abort
  let args = []
  for arg in a:000
    if arg =~ '^[A-Za-z0-9_/.-]\+$'
      let args += [arg]
    else
      let args += [shellescape(arg)]
    endif
  endfor
  return join(args, ' ')
endfunction

let s:flags = '\%(:[p8~.htre]\|:g\=s\(\.\).\{-\}\1.\{-\}\1\)*'
let s:expandable = '\\*\%(<\w\+>\|%\|#\d*\)' . s:flags
function! dispatch#expand(string) abort
  return substitute(a:string, s:expandable, '\=s:expand(submatch(0))', 'g')
endfunction

function! s:expand(string)
  let slashes = len(matchstr(a:string, '^\%(\\\\\)*'))
  return repeat('\', slashes/2) . expand(a:string[slashes : -1])
endfunction

function! dispatch#slash() abort
  return !exists("+shellslash") || &shellslash ? '/' : '\'
endfunction

function! dispatch#shellpipe(file) abort
  if &shellpipe =~# '%s'
    return ' ' . printf(&shellpipe, dispatch#shellescape(a:file))
  else
    return ' ' . &shellpipe . ' ' . dispatch#shellescape(a:file)
  endif
endfunction

function! dispatch#vim_executable() abort
  if !exists('s:vim')
    if has('win32')
      let root = fnamemodify($VIMRUNTIME, ':8') . dispatch#slash()
    elseif has('gui_macvim')
      let root = fnamemodify($VIM, ':h:h') . '/MacOS/'
    else
      let root = fnamemodify($VIM, ':h:h') . '/bin/'
    endif
    if executable(root . v:progname)
      let s:vim = root . v:progname
    elseif executable(v:progname)
      let s:vim = v:progname
    else
      let s:vim = 'vim'
    endif
  endif
  return s:vim
endfunction

function! dispatch#callback(request) abort
  if !empty(v:servername)
    return dispatch#shellescape(dispatch#vim_executable()) .
          \ ' --servername ' . dispatch#shellescape(v:servername) .
          \ ' --remote-expr "' . 'DispatchComplete(' . s:request(a:request).id . ')' . '"'
  endif
  return ''
endfunction

function! dispatch#prepare_make(request, ...) abort
  let exec = 'echo $$ > ' . a:request.file . '.pid; '
  if executable('perl')
    let exec .= 'perl -e "select(undef,undef,undef,0.1)"; '
  else
    let exec .= 'sleep 1; '
  endif
  let exec .= a:0 ? a:1 : (a:request.expanded . dispatch#shellpipe(a:request.file))

  let after = 'rm -f ' . a:request.file . '.pid; ' .
        \ 'touch ' . a:request.file . '.complete; ' .
        \ dispatch#callback(a:request)
  if &shellpipe =~# '2>&1'
    return 'trap ' . shellescape(after) . ' EXIT INT TERM; ' . exec
  else
    " csh
    return exec . '; ' . after
  endif
endfunction

function! dispatch#set_title(request)
  return dispatch#shellescape('printf',
        \ '\033]1;%s\007\033]2;%s\007',
        \ a:request.title,
        \ a:request.expanded)
endfunction

function! dispatch#isolate(...)
  let command = ['cd ' . shellescape(getcwd())]
  for line in split(system('env'), "\n")
    let var = matchstr(line, '^\w\+\ze=')
    if !empty(var) && var !=# '_'
      if &shell =~# 'csh'
        let command += ['setenv '.var.' '.shellescape(eval('$'.var))]
      else
        let command += ['export '.var.'='.shellescape(eval('$'.var))]
      endif
    endif
  endfor
  let command += a:000
  let temp = tempname()
  call writefile(command, temp)
  return 'env -i ' . &shell . ' ' . temp
endfunction

function! s:set_current_compiler(name)
  if empty(a:name)
    unlet! b:current_compiler
  else
    let b:current_compiler = a:name
  endif
endfunction

function! s:dispatch(request) abort
  for handler in g:dispatch_handlers
    let response = call('dispatch#'.handler.'#handle', [a:request])
    if !empty(response)
      redraw
      echo ':!'.a:request.expanded . ' ('.handler.')'
      return 1
    endif
  endfor
  return 0
endfunction

" }}}1
" :Start {{{1

function! dispatch#start(command, ...) abort
  let title = matchstr(a:command, '-title=\zs\%(\\.\|\S\)*')
  if !empty(title)
    let command = a:command[strlen(title) + 8 : -1]
  else
    let command = a:command
  endif
  if empty(command)
    let command = &shell
  endif
  if empty(title)
    let title = fnamemodify(matchstr(command, '\%(\\.\|\S\)\+'), ':t:r')
  endif
  let title = substitute(title, '\\\(\s\)', '\1', 'g')
  let request = extend({
        \ 'action': 'start',
        \ 'background': 0,
        \ 'command': command,
        \ 'directory': getcwd(),
        \ 'expanded': dispatch#expand(command),
        \ 'title': title,
        \ }, a:0 ? a:1 : {})
  if !s:dispatch(request)
    execute '!' . request.command
  endif
  return ''
endfunction

" }}}1
" :Dispatch, :Make {{{1

function! dispatch#compiler_for_program(program) abort
  if a:program ==# 'make'
    return 'make'
  endif
  for plugin in reverse(split(globpath(escape(&rtp, ' '), 'compiler/*.vim', 1), "\n"))
    for line in readfile(plugin, '', 100)
      if matchstr(line, '\<CompilerSet\s\+makeprg=\zs[[:alnum:]_]\+') == a:program
        return fnamemodify(plugin, ':t:r')
      endif
    endfor
  endfor
  return ''
endfunction

function! dispatch#compiler_options(compiler) abort
  let current_compiler = get(b:, 'current_compiler', '')
  let makeprg = &l:makeprg
  let efm = &l:efm

  try
    if a:compiler ==# 'make'
      if &makeprg !=# 'make'
        setlocal efm&
      endif
      return {'program': 'make', 'format': &efm}
    endif
    let &l:makeprg = ''
    execute 'compiler '.fnameescape(a:compiler)
    let options = {'format': &errorformat}
    if !empty(&l:makeprg)
      let options.program = &l:makeprg
    endif
    return options
  finally
    let &l:makeprg = makeprg
    let &l:efm = efm
    call s:set_current_compiler(current_compiler)
  endtry
endfunction

function! dispatch#command_complete(A, L, P) abort
  if a:L =~# '\S\+\s\S\+\s'
    return join(map(split(glob(a:A.'*'), "\n"), 'isdirectory(v:val) ? v:val . dispatch#slash() : v:val'), "\n")
  else
    let executables = []
    for dir in split($PATH, has('win32') ? ';' : ':')
      let executables += map(split(glob(dir.'/'.a:A.'*'), "\n"), 'v:val[strlen(dir)+1 : -1]')
    endfor
    return join(sort(dispatch#uniq(executables)), "\n")
  endif
endfunction

if !exists('s:makes')
  let s:makes = []
  let s:files = {}
endif

function! dispatch#compile_command(bang, args) abort
  if !empty(a:args)
    let args = a:args
  else
    let args = '_'
    for vars in [b:, g:, t:, w:]
      if has_key(vars, 'dispatch')
        let args = vars.dispatch
      endif
    endfor
  endif

  if args =~# '^!'
    return 'Start' . (a:bang ? '!' : '') . ' ' . args[1:-1]
  endif
  let executable = matchstr(args, '\S\+')

  let request = {
        \ 'action': 'make',
        \ 'background': a:bang,
        \ 'directory': getcwd(),
        \ 'format': '%+G%.%#'
        \ }

  if executable ==# '_'
    let request.args = matchstr(args, '_\s*\zs.*')
    let request.program = &makeprg
    if &makeprg =~# '\$\*'
      let request.command = substitute(&makeprg, '\$\*', request.args, 'g')
    elseif empty(request.args)
      let request.command = &makeprg
    else
      let request.command = &makeprg . ' ' . request.args
    endif
    let request.format = &errorformat
    let request.compiler = get((empty(&l:makeprg) ? g: : b:), 'current_compiler', '')
  else
    let request.compiler = dispatch#compiler_for_program(fnamemodify(executable, ':t:r'))
    if !empty(request.compiler)
      call extend(request,dispatch#compiler_options(request.compiler))
    endif
    let request.command = args
  endif

  if empty(request.compiler)
    unlet request.compiler
  endif
  let request.title = get(request, 'compiler', 'make')

  if &autowrite
    wall
  endif

  let request.expanded = dispatch#expand(request.command)
  let request.file = tempname()
  call extend(s:makes, [request])
  let request.id = len(s:makes)
  let s:files[request.file] = request
  let &errorfile = request.file

  cclose
  if !s:dispatch(request)
    execute '!'.request.command dispatch#shellpipe(request.file)
    call dispatch#complete(request.id, 'quiet')
  endif
  return ''
endfunction

" }}}1
" :FocusDispatch {{{1

function! dispatch#focus() abort
  if exists('w:dispatch')
    let [compiler, why] = [w:dispatch, 'Window local focus']
  elseif exists('t:dispatch')
    let [compiler, why] = [t:dispatch, 'Tab local focus']
  elseif exists('g:dispatch')
    let [compiler, why] = [g:dispatch, 'Global focus']
  elseif exists('b:dispatch')
    let [compiler, why] = [b:dispatch, 'Buffer default']
  elseif !empty(&l:makeprg)
    return [':Make', 'Buffer default']
  else
    return [':Make', 'Global default']
  endif
  if compiler =~# '^_\>'
    return [':Make' . compiler[1:-1], why]
  elseif compiler =~# '^!'
    return [':Start ' . compiler[1:-1], why]
  else
    return [':Dispatch ' . compiler, why]
  endif
endfunction

function! dispatch#focus_command(bang, args) abort
  if empty(a:args) && a:bang
    unlet! w:dispatch t:dispatch g:dispatch
    let [what, why] = dispatch#focus()
    echo 'Reverted default to ' . what
  elseif empty(a:args)
    let [what, why] = dispatch#focus()
    echo printf('%s is %s', why, what)
  elseif a:bang
    let w:dispatch = escape(dispatch#expand(a:args), '#%')
    let [what, why] = dispatch#focus()
    echo 'Set window local focus to ' . what
  else
    unlet! w:dispatch t:dispatch
    let g:dispatch = escape(dispatch#expand(a:args), '#%')
    let [what, why] = dispatch#focus()
    echo 'Set global focus to ' . what
  endif
  return ''
endfunction

" }}}1
" Requests {{{1

function! s:file(request) abort
  if type(a:request) == type('')
    return a:request
  elseif type(a:request) == type({})
    return get(a:request, 'file', '')
  else
    return get(get(s:makes, a:request-1, {}), 'file', '')
  endif
endfunction

function! s:request(request) abort
  if type(a:request) == type({})
    return a:request
  elseif type(a:request) == type(0)
    return get(s:makes, a:request-1, {})
  else
    return get(s:files, a:request, {})
  endif
endfunction

function! dispatch#completed(request) abort
  return get(s:request(a:request), 'completed', 0)
endfunction

function! dispatch#complete(file, ...) abort
  if !dispatch#completed(a:file)
    let request = s:request(a:file)
    let request.completed = 1
    if !a:0
      if has_key(request, 'args')
        echo 'Finished :Make' request.args
      else
        echo 'Finished :Dispatch' request.command
      endif
    endif
    if !request.background
      call s:cgetfile(request, 0, 0)
      redraw
    endif
  endif
  return ''
endfunction

" }}}1
" Quickfix window {{{1

function! dispatch#copen(bang) abort
  if empty(s:makes)
    return 'echoerr ' . string('No dispatches yet')
  endif
  let request = s:makes[-1]
  if !dispatch#completed(request) && filereadable(request.file . '.complete')
    let request.completed = 1
  endif
  call s:cgetfile(request, a:bang, 1)
endfunction

function! s:cgetfile(request, all, copen) abort
  let request = s:request(a:request)
  let efm = &l:efm
  let makeprg = &l:makeprg
  let compiler = get(b:, 'current_compiler', '')
  let cd = haslocaldir() ? 'lcd' : 'cd'
  let dir = getcwd()
  try
    call s:set_current_compiler(get(request, 'compiler', ''))
    exe cd request.directory
    if a:all
      let &l:efm = '%+G%.%#'
    else
      let &l:efm = request.format
    endif
    let &l:makeprg = request.command
    execute 'cgetfile '.fnameescape(request.file)
    silent doautocmd QuickFixCmdPost cgetfile
  catch '^E40:'
    return v:exception
  finally
    exe cd dir
    let &l:efm = efm
    let &l:makeprg = makeprg
    call s:set_current_compiler(compiler)
  endtry
  call s:open_quickfix(request, a:copen)
endfunction

function! s:open_quickfix(request, copen) abort
  let was_qf = &buftype ==# 'quickfix'
  execute 'botright' (!empty(getqflist()) || a:copen) ? 'copen' : 'cwindow'
  if &buftype ==# 'quickfix' && !was_qf && !a:copen
    wincmd p
  endif
  for winnr in range(1, winnr('$'))
    if getwinvar(winnr, '&buftype') ==# 'quickfix'
      call setwinvar(winnr, 'quickfix_title', ':' . a:request.expanded)
      let bufnr = winbufnr(winnr)
      call setbufvar(bufnr, '&efm', a:request.format)
      call setbufvar(bufnr, 'dispatch', escape(a:request.expanded, '%#'))
      if has_key(a:request, 'program')
        call setbufvar(bufnr, '&makeprg', a:request.program)
      endif
      if has_key(a:request, 'compiler')
        call setbufvar(bufnr, 'current_compiler', a:request.compiler)
      endif
    endif
  endfor
endfunction

" }}}1
