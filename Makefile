luacc.so : luacc.c
	gcc -g -Wall --shared -fPIC -o $@ $^ -ltcc