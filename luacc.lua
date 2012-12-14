local newstate = require "luacc.core"

local type_funcs_define = ""
local type_define = ""
local cfunction_define = ""
local codes = {}
local types = {}
local import_funcs = {}
local c_funcs = {}
local info = {
	bytes = 0,
	state = 0,
	struct = 0,
	cfunction = 0,
	routine = 0;
}

local luacc = {}

local function extract_desc(source)
	local from = assert(string.find(source, "\n%s+[^[]"))
	return string.sub(source, 1, from-1), string.sub(source,from)
end

local function parser_desc(desc)
	local ret = { param = {} , result = {} }
	for attrib, name, type in string.gmatch(desc, "%s*%[(%a+)%]%s*([%w_]+)%s+([%a_]+)[^\n]*") do
		local v = { name = name , type = type, attrib = attrib }
		table.insert( attrib == "ret" and ret.result or ret.param, v)
	end
	return ret
end

local stddef = [[
#ifndef true
typedef int bool;
#define true 1
#define false 0
#endif
#ifndef NULL
#define NULL (void*)0
#endif
typedef const void * object;
typedef unsigned long int size_t;
]]

local lua_api = [[
typedef struct lua_State lua_State;
typedef double lua_Number;

int lua_checkstack(lua_State *L, int extra);
void lua_pushnumber(lua_State *L, lua_Number n);
lua_Number lua_tonumberx(lua_State *L, int index, int *isnum);
void lua_settop(lua_State *L, int index);
int lua_gettop(lua_State *L);
int luaL_error(lua_State *L, ...);
int lua_toboolean(lua_State *L, int index);
const void * lua_topointer(lua_State *L, int index);
void lua_pushboolean(lua_State *L, int b);
const char *lua_tolstring(lua_State *L,int index, size_t *len);
const char *lua_pushstring(lua_State *L, const char *s);
void lua_getfield (lua_State *L, int index, const char *k);
void lua_setfield (lua_State *L, int index, const char *k);
void lua_pushnil (lua_State *L);
void lua_rawgetp (lua_State *L, int index, const void *p);
void lua_rawsetp (lua_State *L, int index, const void *p);
void lua_pushvalue (lua_State *L, int index);
void lua_createtable (lua_State *L, int narr, int nrec);
void lua_replace (lua_State *L, int index);
#define lua_pop(L,n)		lua_settop(L, -(n)-1)

]]

local ctype_conv = {
	int = "int",
	float = "float",
	double = "double",
	string = "const char *",
	bool = "int",
	object = "const void *",
}

local struct_define_pattern = [[
	typedef struct {
		$FIELDS;
	} $STRUCTNAME;

]]

local struct_getter_header = [[
$LAST

void __$TYPENAME__get(lua_State *L, int index, $TYPENAME *t $HASOBJECT);
void __$TYPENAME__set(lua_State *L, int index, $TYPENAME *t , int objindex);

]]

local struct_getter_pattern = [[
$STDDEF
$INCLUDE
$STRUCTD

void __get__(lua_State *L, int index, $TYPENAME *t $HASOBJECT) {
	$GSOURCE
}

void __set__(lua_State *L, int index, $TYPENAME *t , int objindex) {
	if (index == 0) {
		lua_createtable(L, 0, $SNUMBER);
		index = -2;
		objindex = 1;
	}
	$SSOURCE
}

]]

local function struct_getter(name, struct, structd)
	local temp = {}
	local temp2 = {}
	local has_object
	local n = 0
	for name,type in pairs(struct) do
		n = n + 1
		table.insert(temp, 'lua_getfield(L, index, "'.. name ..'");')
		if type == "object" then
			table.insert(temp, "t->"..name.."= lua_topointer(L,-1);")
			table.insert(temp, "if (t->"..name..") lua_rawsetp(L, objindex, t->" .. name .. ");")
			table.insert(temp2, "if (t->"..name..") lua_rawgetp(L, objindex, t->"..name.."); else lua_pushnil(L);")
			has_object = true
		else
			if type == "int" or type == "float" or type == "double" then
				table.insert(temp, "t->"..name.."=("..type..")lua_tonumberx(L,-1,NULL);")
				table.insert(temp2, "lua_pushnumber(L, ("..type..")t->" .. name ..");")
			elseif type == "boolean" then
				table.insert(temp, "t->"..name.."= lua_toboolean(L,-1);")
				table.insert(temp2, "lua_pushboolean(L, t->" .. name ..");")
			elseif type == "string" then
				table.insert(temp, "t->"..name.."= lua_tolstring(L,-1,NULL);")
				table.insert(temp2, "if (t->"..name.."==NULL) lua_pushnil(L); else lua_pushstring(L, t->" .. name ..");")
			end
			table.insert(temp, "lua_pop(L,1);")
		end
		table.insert(temp2, 'lua_setfield(L, index, "'..name..'");')
	end

	local objindex = has_object and ", int objindex" or ""
	local pat =	{
		STDDEF = stddef,
		INCLUDE = lua_api,
		TYPENAME = name ,
		IMPORT = headers ,
		STRUCTD = structd ,
		HASOBJECT = objindex,
		GSOURCE = table.concat(temp, "\n"),
		SSOURCE = table.concat(temp2, "\n"),
		SNUMBER = n,
		LAST = type_funcs_define,
	}

	local source = string.gsub( struct_getter_pattern, "%$(%u+)",pat)

	local state = newstate()
	state:api()
	assert(state:compile(source))
	local sz = assert(state:relocate())
	info.bytes = info.bytes + sz
	local export = {
		__get__ = true,
		__set__ = true,
	}
	state:export(export)
	import_funcs["__"..name.."__get"] = export.__get__
	import_funcs["__"..name.."__set"] = export.__set__
	state:close()
	table.insert(codes , state)

	type_funcs_define = string.gsub( struct_getter_header, "%$(%u+)",pat)

	return has_object
end

function luacc.struct(name, struct)
	assert(types[name] == nil)
	types[name] = false
	local temp = {}
	for name,type in pairs(struct) do
		local ctype = assert(ctype_conv[type])
		table.insert(temp, ctype .. " " .. name)
	end
	local d = string.gsub( struct_define_pattern, "%$(%u+)", { STRUCTNAME = name , FIELDS = table.concat(temp, ";\n") })
	type_define = type_define .. d
	if struct_getter(name, struct, d) then
		types[name] = "objects"
	end
end

local tcc_pattern = [[
$STDDEF
$INCLUDE
$STRUCTS
$IMPORTS
$GETFUNCS

int $FUNCNAME(lua_State *_L) {
	int __objref = lua_gettop(_L);
	if (__objref != $NPARAM)
		return luaL_error(_L, "Need $NPARAM params, got %d", __objref);
	$HASOBJECT
	$VAR
#define return goto __return
	$SOURCE
__return:
#undef return
	$OUTPUT
	$OBJREF
	$RETURN
	return $NRESULT;
}
]]



local function gen_var(desc)
	local max = math.max(#desc.param,#desc.result)
	local t = { "lua_checkstack(_L, " .. max+10 .. ");" }
	local has_object
	for k , v in ipairs(desc.param) do
		if v.attrib == "in" or v.attrib == "inout" then
			if v.type == "int" or v.type == "float" or v.type == "double" then
				table.insert(t, v.type .. " " .. v.name .. " = (" .. v.type .. ")lua_tonumberx(_L, " .. k ..", NULL);")
			elseif v.type == "bool" then
				table.insert(t, "bool " .. v.name .. " = lua_toboolean(_L, " .. k ..");")
			elseif v.type == "string" then
				table.insert(t, "const char *" .. v.name .. " = lua_tolstring(_L, " .. k ..", NULL);")
			elseif v.type == "object" then
				table.insert(t, "const void *" .. v.name .. " = lua_topointer(_L, " .. k ..");")
				table.insert(t, "if (" .. v.name .. ") { lua_pushvalue(_L," .. k .."); lua_rawsetp(_L, __objref, ".. v.name .."); }")
				has_object = true
			else
				local ho = types[v.type]
				assert(ho ~= nil,  "Don't support in type : " .. v.type)
				table.insert(t, v.type .. " " .. v.name .. ";")
				if ho then
					table.insert(t, "__" .. v.type .. "__get(_L, " .. k .. ",&" .. v.name .. ", __objref);")
					hash_object = true
				else
					table.insert(t, "__" .. v.type .. "__get(_L, " .. k .. ",&" .. v.name .. ");")
				end
			end
		end
	end
	return table.concat(t, "\n") , has_object
end

local function gen_ret(result)
	local t = {}
	for _ , v in ipairs(result) do
		if v.type == "int" or v.type == "float" or v.type == "double" then
			table.insert(t, "lua_pushnumber(_L, (lua_Number)" .. v.name .. ");")
		elseif v.type == "bool" then
			table.insert(t, "lua_pushboolean(_L, " .. v.name .. ");")
		elseif v.type == "string" then
			table.insert(t, "if ("..v.name..") lua_pushstring(_L, " .. v.name .. "); else lua_pushnil(_L); ")
		elseif v.type == "object" then
			table.insert(t, "if ("..v.name..") { lua_rawgetp(_L, 1, "..v.name.."); } else lua_pushnil(_L);")
		else
			assert(types[v.type] ~= nil,  "Don't support ret type : " .. v.type)
			table.insert(t, "__" .. v.type .. "__set(_L, 0, &" .. v.name ..", __objref);")
		end
	end

	return table.concat(t, "\n")
end

local function gen_out(param)
	local t = {}
	for k , v in ipairs(param) do
		if v.attrib == "out" or v.attrib == "inout" then
			assert(types[v.type] ~= nil,  "Don't support out type : " .. v.type)
			table.insert(t, "__" .. v.type .. "__set(_L, "..k..", &" .. v.name ..", __objref);")
		end
	end
	return table.concat(t, "\n")
end

function luacc.routine(source)
	local desc, source = extract_desc(source)
	desc = parser_desc(desc)
	local var, has_object = gen_var(desc)
	local temp = {
		STDDEF = stddef,
		FUNCNAME = "__routine__",
		INCLUDE = lua_api,
		IMPORTS = cfunction_define,
		STRUCTS = type_define,
		GETFUNCS = type_funcs_define,
		SOURCE = source ,
		NPARAM = tostring(#desc.param),
		NRESULT = tostring(#desc.result),
		HASOBJECT = has_object and "++__objref; lua_createtable(_L,0,0);" or "",
		VAR = var,
		OUTPUT = gen_out(desc.param),
		OBJREF = has_object and "lua_replace(_L,1); lua_settop(_L,1);" or "lua_settop(_L, 0);",
		RETURN = gen_ret(desc.result)
	}
	source = string.gsub( tcc_pattern, "%$(%u+)", temp)

	local state = newstate()
	state:api()
	state:import(import_funcs)

	assert(state:compile(source))
	local sz = assert(state:relocate())
	info.bytes = info.bytes + sz
	local f = state:routine(temp.FUNCNAME)
	state:close()
	table.insert(codes , state)
	info.routine = info.routine + 1
	return f
end

local cfunction_pattern = [[
$STDDEF
$STRUCTS
$IMPORTS

$SOURCE
]]

function luacc.cfunction(source)
	local state = newstate()
	state:import(c_funcs)

	source = string.gsub( cfunction_pattern, "%$(%u+)", {
		STDDEF = stddef,
		STRUCTS = type_define,
		IMPORTS = cfunction_define,
		SOURCE = source,
	})
	assert(state:compile(source))
	local sz = assert(state:relocate())
	info.bytes = info.bytes + sz

	local export = {}
	local fdefine = {}
	for type, name, param, padding in string.gmatch(source, "([%w_]+)%s+([%w_]+)(%b())%s*([;{])") do
		if padding == '{' then
			export[name] = true
			table.insert(fdefine, type .. " " .. name .. param .. ";")
		end
	end
	table.insert(fdefine, "")

	cfunction_define = cfunction_define .. table.concat(fdefine, "\n")

	state:export(export)

	for k,v in pairs(export) do
		c_funcs[k] = v
		import_funcs[k] = v
	end

	state:close()
	table.insert(codes , state)
end

local function count_table(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

function luacc.info()
	info.state = #codes
	info.cfunction = count_table(c_funcs)
	info.struct = count_table(types)
	return info
end

return luacc
