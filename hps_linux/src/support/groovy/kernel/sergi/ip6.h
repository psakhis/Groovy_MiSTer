#ifndef  __IP6_H__
#define __IP6_H__

#include <sys/types.h>
#include <string.h>

#define IPV6_SIZE 16

typedef __u16 u16;
typedef __u32 u32;
typedef __u64 u64;

typedef unsigned char u8;

/*
 * pl: prefix len
 * size: sub size
 *
 * pl, size MUST bee the multiples of 8
 * */
static inline u32 ip6_slice(struct in6_addr *ip6, u8 pl, u8 size)
{
	u32 v = 0;
	u8 *ip;

	ip = ip6->s6_addr + (pl >> 3);

	for (; size; size = size - 8) {
		v = (v << 8) + *ip;
		++ip;
	}

	return v;
}

static inline void ip6_cpy(struct in6_addr *dst, struct in6_addr *src)
{
	memcpy(dst->s6_addr, src->s6_addr, IPV6_SIZE);
}

static inline void ip6_copy_prefix(struct in6_addr *dst,
				   struct in6_addr *src, u8 size)
{
	u8 off, l, m;

	off = size / 8;
	l = size % 8;

	memcpy(dst->s6_addr, src->s6_addr, off);

	if (l) {
		m = 0xFF;
		m = ~(m >> l);
		dst->s6_addr[off + 1] = src->s6_addr[off + 1] & m;
	}
}

static inline bool ip6_cmp(struct in6_addr *dst, struct in6_addr *src, u8 size)
{
	u8 *d1, *d2;
	u8 t1, t2;
	u8 s;

	d1 = dst->s6_addr;
	d2 = src->s6_addr;

#define _v6_prefix_cmp(s) {		\
	if (*(u##s *)d1 != *(u##s *)d2)	\
		return false;		\
	d1 += s / 8;			\
	d2 += s / 8;			\
}

#define _cmp8() _v6_prefix_cmp(8)
#define _cmp16() _v6_prefix_cmp(16)
#define _cmp24() _cmp16();_cmp8()
#define _cmp32() _v6_prefix_cmp(32)
#define _cmp64() _v6_prefix_cmp(64)

	s = size >> 3;

	switch(s) {
	case 0: break;
	case 1: _cmp8(); break;
	case 2: _cmp16(); break;
	case 3: _cmp24(); break;
	case 4: _cmp32(); break;
	case 5: _cmp32(); _cmp8(); break;
	case 6: _cmp32(); _cmp16(); break;
	case 7: _cmp32(); _cmp24(); break;
	case 8: _cmp64(); break;
	case 9:  _cmp64(); _cmp8();  break;
	case 10: _cmp64(); _cmp16(); break;
	case 11: _cmp64(); _cmp24(); break;
	case 12: _cmp64(); _cmp32(); break;
	case 13: _cmp64(); _cmp32(); _cmp8();  break;
	case 14: _cmp64(); _cmp32(); _cmp16(); break;
	case 15: _cmp64(); _cmp32(); _cmp24(); break;
	case 16: _cmp64(); _cmp64(); return true;
	};

	s = size & 0x7;

	if (s) {
		t1 = (*d1) >> (8 - s);
		t2 = (*d2) >> (8 - s);
		return t1 == t2;
	}

	return true;
}

static inline bool ip6_eq(struct in6_addr *dst, struct in6_addr *src)
{
	return ip6_cmp(dst, src, 128);
}

static inline bool ip6_is_zero(struct in6_addr *dst)
{
	struct in6_addr p = {};

	return ip6_eq(dst, &p);
}

#endif


