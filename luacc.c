#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include "libtcc.h"

#define TCCSTATE "tccstate"

struct ts {
	struct TCCState *state;
	void * code;
};

static int
ldelete(lua_State *L) {
	struct ts *t = lua_touserdata(L,1);
	if (t->state) {
		tcc_delete(t->state);
		t->state = NULL;
	}
	if (t->code) {
		free(t->code);
		t->code = NULL;
	}
	return 0;
}

static void
errfunc(void *ud, const char *msg) {
	lua_State *L = ud;
	if (!lua_istable(L,-1)) {
		lua_newtable(L);
	}
	int n = lua_rawlen(L,-1);
	lua_pushstring(L, msg);
	lua_rawseti(L, -2, n+1);
}

static int
throw_err(lua_State *L,struct ts *t) {
	if (t->code == NULL) {
		free(t->code);
		t->code = NULL;
	}
	tcc_delete(t->state);
	t->state = NULL;

	if (!lua_istable(L,-1)) {
		lua_pushboolean(L, 0);
		lua_pushstring(L, "compile error");
		return 2;
	}
	int errtbl = lua_gettop(L);
	luaL_Buffer b;
	luaL_buffinit(L, &b);
	int n = lua_rawlen(L,errtbl);
	int i;
	for (i=1;i<=n;i++) {
		lua_rawgeti(L,errtbl,i);
		luaL_addvalue(&b);
		luaL_addchar(&b, '\n');
	}
	luaL_pushresult(&b);
	lua_pushboolean(L, 0);
	lua_insert(L, -2);
	return 2;
}

static struct ts * 
_check(lua_State *L, const char *err) {
	struct ts * t = luaL_checkudata(L, 1, TCCSTATE);
	if (t->state == NULL) {
		luaL_error(L, "%s to a closed state %p", err, t);
	}
	if (t->code) {
		luaL_error(L, "%s to a relocated state %p", err, t);
	}
	return t;
}

static int
lrelocate(lua_State *L) {
	struct ts * t = _check(L, "Relocate");

	int sz = tcc_relocate(t->state, NULL);
	if (sz < 0) {
		return throw_err(L,t);
	}
	t->code = malloc(sz);
	int err = tcc_relocate(t->state, t->code);
	if (err <0) {
		return throw_err(L,t);
	}
	lua_pushinteger(L,sz);
	return 1;
}

static int
lcompile(lua_State *L) {
	struct ts * t = _check(L, "Compile");
	const char * source = luaL_checkstring(L,2);
	tcc_set_error_func(t->state, L, errfunc);
	int err = tcc_compile_string(t->state, source);
	if (err) {
		return throw_err(L,t);
	}
	lua_pushboolean(L,1);
	return 1;
}

static struct ts * 
_check_export(lua_State *L, const char *err) {
	struct ts * t = luaL_checkudata(L, 1, TCCSTATE);
	if (t->state == NULL) {
		luaL_error(L, "%s from a closed state %p", err, t);
	}
	if (t->code == NULL) {
		luaL_error(L, "%s from a unrelocate state %p", err, t);
	}
	return t;
}

static int
lroutine(lua_State *L) {
	struct ts * t = _check_export(L, "Export routine");
	const char * name = luaL_checkstring(L, 2);
	lua_CFunction f = (lua_CFunction)tcc_get_symbol(t->state, name);
	if (f == NULL) {
		return luaL_error(L, "Can't get %s from state %p", name, t);
	}
	lua_pushcfunction(L, f);
	return 1;
}

static int
lexport(lua_State *L) {
	struct ts * t = _check_export(L, "Export");
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_pushnil(L);
	while  (lua_next(L, 2) != 0) {
		lua_pop(L,1);
		lua_pushvalue(L,-1);
		const char * name = luaL_checkstring(L, -1);
		void *f = tcc_get_symbol(t->state, name);
		if (f == NULL) {
			return luaL_error(L, "Can't find %s in state %p", name, t);
		}
		lua_pushlightuserdata(L, f);
		lua_settable(L, 2);
	}

	return 0;
}

static int
limport(lua_State *L) {
	struct ts * t = _check(L, "Import");
	luaL_checktype(L, 2, LUA_TTABLE);
	lua_pushnil(L);
	while  (lua_next(L, 2) != 0) {
		luaL_checktype(L, -2, LUA_TSTRING);
		luaL_checktype(L, -1, LUA_TLIGHTUSERDATA);
		const char * name = lua_tostring(L, -2);
		void * func = lua_touserdata(L,-1);
		tcc_add_symbol(t->state, name, func);
		lua_pop(L,1);
	}
	return 0;
}

#define FUNC(x) tcc_add_symbol(state, #x , (const void *)x);

static void
import_sym(struct TCCState *state) {
	FUNC(lua_checkstack)
	FUNC(lua_pushnumber)
	FUNC(lua_tonumberx)
	FUNC(lua_settop)
	FUNC(lua_gettop)
	FUNC(luaL_error)
	FUNC(lua_pushboolean)
	FUNC(lua_toboolean)
	FUNC(lua_tolstring)
	FUNC(lua_topointer)
	FUNC(lua_pushstring)
	FUNC(lua_getfield)
	FUNC(lua_setfield)
	FUNC(lua_pushnil)
	FUNC(lua_rawgetp)
	FUNC(lua_rawsetp)
	FUNC(lua_pushvalue)
	FUNC(lua_createtable)
	FUNC(lua_replace)
}

static int
lapi(lua_State *L) {
	struct ts * t = _check(L, "Import api");
	import_sym(t->state);

	return 0;
}

static int
lclose(lua_State *L) {
	struct ts * t = luaL_checkudata(L, 1, TCCSTATE);
	if (t->state == NULL) {
		return luaL_error(L, "Don't close twice %p", t);
	}
	tcc_delete(t->state);
	t->state = NULL;
	return 0;
}

static int
lopen(lua_State *L) {
	struct ts * t = lua_newuserdata(L, sizeof(*t));
	t->code = NULL;
	t->state = tcc_new();
	
	if (luaL_newmetatable(L, TCCSTATE)) {
		luaL_Reg l[] = {
			{ "close", lclose },
			{ "api", lapi },
			{ "import", limport },
			{ "export", lexport },
			{ "compile", lcompile },
			{ "relocate", lrelocate },
			{ "routine", lroutine },
			{ NULL , NULL },
		};
		luaL_newlib(L,l);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, ldelete);
		lua_setfield(L, -2, "__gc");
	}
	lua_setmetatable(L, -2);
	return 1;
}

int
luaopen_luacc_core(lua_State *L) {
	luaL_checkversion(L);
	lua_pushcfunction(L, lopen);

	return 1;
}
