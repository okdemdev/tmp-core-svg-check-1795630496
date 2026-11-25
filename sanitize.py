#!/usr/bin/env python3
"""Build sanitized variants of an SVG that avoid CoreSVG's bare `opacity` path.

Variant A ("fillopacity"): every bare opacity="a" becomes fill-opacity="a"
Variant B ("baked"): opacity is folded into fill/stroke colors as #RRGGBBAA and
                     the opacity attribute is removed entirely.
"""
import re
import sys

HEX = re.compile(r"^#([0-9a-fA-F]{6})$")


def bake(color, alpha):
    m = HEX.match(color.strip())
    if not m:
        return None
    a = max(0, min(255, round(float(alpha) * 255)))
    return f"#{m.group(1).upper()}{a:02X}"


def parse_attrs(tag):
    return dict(re.findall(r'([\w:-]+)="([^"]*)"', tag))


def rebuild(tag, attrs, order):
    name = re.match(r"<([\w:-]+)", tag).group(1)
    selfclose = tag.rstrip().endswith("/>")
    parts = [f"{k}=\"{attrs[k]}\"" for k in order if k in attrs]
    return f"<{name} " + " ".join(parts) + (" />" if selfclose else ">")


def main(mode, src, dst):
    s = open(src).read()

    def repl(m):
        tag = m.group(0)
        attrs = parse_attrs(tag)
        order = [k for k in re.findall(r'([\w:-]+)="', tag)]
        if "opacity" not in attrs:
            return tag
        alpha = attrs.pop("opacity")
        if mode == "fillopacity":
            # Preserve stroke opacity too, so the result looks identical.
            attrs["fill-opacity"] = alpha
            if "stroke" in attrs:
                attrs["stroke-opacity"] = alpha
        elif mode == "baked":
            for key in ("fill", "stroke"):
                if key in attrs:
                    baked = bake(attrs[key], alpha)
                    if baked:
                        attrs[key] = baked
        return rebuild(tag, attrs, order)

    out = re.sub(r"<[^>]*\bopacity=\"[^\"]*\"[^>]*>", repl, s)
    open(dst, "w").write(out)
    print(f"wrote {dst} ({len(out)} bytes, {out.count('opacity=')} bare opacity left)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
