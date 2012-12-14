LUACC allows you write C code in lua .

It seems like Cython to python.

## Export C routine for lua

```Lua
local luacc = require "luacc"

local f = luacc.routine [[
	[in] a int
	[in] b int
	[ret] c int
	[ret] d int

	int c = a + b;
	int d = a - b;
]]

print(f(2,1))	-- 3	1
```

## Import C function for later call from C routine

```Lua
local luacc = require "luacc"

luacc.cfunction [[

int max(int a, int b) {
	return a > b ? a:b;
}

int min(int a, int b) {
	return a < b ? a:b;
}

]]

local f = luacc.routine [[
	[in] a int
	[in] b int
	[ret] c int
	[ret] d int

	int c = max(a,b);
	int d = min(a,b);
]]

print(f(2,1))	-- 2	1
```

## Define user type

```Lua
local luacc = require "luacc"

luacc.struct ( "foo", { x = "int" , y = "int" })

local luacc.cfunction [[
void swap(foo &f) {
	int temp = f->x;
	f->x = f->y;
	f->y = f->x;
}
]]

local f = luacc.routine [[
	[inout] x foo
	
	swap(&x);
]]

local foo = { x = 1, y = 2}
f(foo)

print(foo.x, foo.y)	-- 2	1
```

It doesn't support nest type yet.

## Build-in types

* int 
* bool
* float
* double
* string	(const char *)
* object	(string table userdata nil)

## Make

* install tcc from http://repo.or.cz/w/tinycc.git
* install lua 5.2
* make

## Question ?

* See test.lua
* Send me an email : http://www.codingnow.com/2000/gmail.gif
* My Blog : http://blog.codingnow.com
