local luacc = require "luacc"

luacc.struct ( "foo", { x = "int" , y = "int" })
luacc.struct ( "mytype", {
	obj = "object",
	n = "int",
})

luacc.cfunction [[
void swap(foo *f) {
	int temp = f->x;
	f->x = f->y;
	f->y = temp;
}
]]

local f = luacc.routine [[
	[inout] a foo
	[ret] x foo

	foo x = a;
	swap(&a);
]]

local p1 = {x=2,y=3}
local p2 = f(p1)

for k,v in pairs(p1) do
	print("p1.",k,v)
end


for k,v in pairs(p2) do
	print("p2.",k,v)
end

local f2 = luacc.routine [[
	[out] obj mytype
	[in] x object
	[in] n int

	mytype obj;
	obj.obj = x;
	obj.n = n;
]]

local x = {}

f2(x, p1, 5)

for k,v in pairs(x) do
	print("x.",k,v)
end

for k,v in pairs(luacc.info()) do
	print("info",k,v)
end
