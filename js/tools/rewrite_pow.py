#!/usr/bin/env python3
"""Replaces every `A ^ B` in a Lua source with `__pow(A, B)`.

The ^ operator on numbers cannot be overridden in Lua, and the reference needs
a deterministic pow (detmath.lua). The parser understands strings, comments,
parentheses and call/index chains (`sin(t) ^ 3`, `(p[i][1] - q) ^ 2`).
A unary minus on the left is not captured: in Lua `-x ^ 2` = -(x ^ 2).

    rewrite_pow.py in.lua out.lua   -> prints the number of replacements
"""
import re
import sys

IDENT = re.compile(r"[A-Za-z_0-9.]")


def skip_spans(src):
    """Positions to skip: strings and comments."""
    mask = [False] * len(src)
    i, n = 0, len(src)
    while i < n:
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            for k in range(i, end): mask[k] = True
            i = end
        elif src[i] in "\"'":
            q, k = src[i], i + 1
            while k < n and src[k] != q:
                k += 2 if src[k] == "\\" else 1
            for j in range(i, min(k + 1, n)): mask[j] = True
            i = k + 1
        elif re.match(r"\[(=*)\[", src[i:]):
            m = re.match(r"\[(=*)\[", src[i:])
            end = src.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            for k in range(i, end): mask[k] = True
            i = end
        else:
            i += 1
    return mask


def left_operand(src, p):
    """Start of the left operand of the ^ at position p."""
    k = p - 1
    while k >= 0 and src[k] in " \t": k -= 1
    end = k + 1
    while True:
        if src[k] in ")]":
            depth, close = 0, src[k]
            opn = "(" if close == ")" else "["
            while True:
                if src[k] == close: depth += 1
                elif src[k] == opn: depth -= 1
                if depth == 0: break
                k -= 1
            k -= 1
            # chain: f(x), a.b[c], t[i][j]
            if k >= 0 and (IDENT.match(src[k]) or src[k] in ")]"):
                continue
            return k + 1, end
        elif IDENT.match(src[k]):
            while k >= 0 and IDENT.match(src[k]): k -= 1
            if k >= 0 and src[k] in ")]":       # a[i].b is rare, but handle it anyway
                continue
            return k + 1, end
        else:
            raise SystemExit(f"cannot parse the left operand at position {p}: {src[max(0, p - 30):p + 5]!r}")


def right_operand(src, p):
    """End of the right operand of the ^ at position p."""
    k = p + 1
    while src[k] in " \t": k += 1
    start = k
    if src[k] == "(":
        depth = 0
        while True:
            if src[k] == "(": depth += 1
            elif src[k] == ")": depth -= 1
            k += 1
            if depth == 0: break
        return start, k
    m = re.match(r"\d+\.?\d*(?:[eE][-+]?\d+)?|[A-Za-z_][A-Za-z_0-9.]*", src[k:])
    if not m:
        raise SystemExit(f"cannot parse the right operand at position {p}: {src[p - 5:p + 30]!r}")
    k += m.end()
    while k < len(src) and src[k] in "([":    # call/index on the right
        close = ")" if src[k] == "(" else "]"
        depth = 0
        while True:
            if src[k] in "([": depth += 1
            elif src[k] in ")]": depth -= 1
            k += 1
            if depth == 0: break
    return start, k


def rewrite(src):
    count = 0
    while True:
        mask = skip_spans(src)
        pos = next((i for i, c in enumerate(src) if c == "^" and not mask[i]), None)
        if pos is None:
            return src, count
        ls, le = left_operand(src, pos)
        rs, re_ = right_operand(src, pos)
        src = src[:ls] + "__pow(" + src[ls:le] + ", " + src[rs:re_] + ")" + src[re_:]
        count += 1


if __name__ == "__main__":
    s = open(sys.argv[1], encoding="utf-8").read()
    out, n = rewrite(s)
    open(sys.argv[2], "w", encoding="utf-8").write(out)
    print(f"{sys.argv[1]}: {n} replacements")
