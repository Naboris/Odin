package odin_html_docs

import doc "core:odin/doc-format"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:path/slashpath"
import "core:sort"
import "core:slice"

GITHUB_LICENSE_URL :: "https://github.com/odin-lang/Odin/tree/master/LICENSE"
GITHUB_CORE_URL :: "https://github.com/odin-lang/Odin/tree/master/core"
BASE_CORE_URL :: "/core"

header:   ^doc.Header
files:    []doc.File
pkgs:     []doc.Pkg
entities: []doc.Entity
types:    []doc.Type

pkgs_to_use: map[string]^doc.Pkg // trimmed path
pkg_to_path: map[^doc.Pkg]string // trimmed path

array :: proc(a: $A/doc.Array($T)) -> []T {
	return doc.from_array(header, a)
}
str :: proc(s: $A/doc.String) -> string {
	return doc.from_string(header, s)
}

errorf :: proc(format: string, args: ..any) -> ! {
	fmt.eprintf("%s ", os.args[0])
	fmt.eprintf(format, ..args)
	fmt.eprintln()
	os.exit(1)
}

base_type :: proc(t: doc.Type) -> doc.Type {
	t := t
	for {
		if t.kind != .Named {
			break
		}
		t = types[array(t.types)[0]]
	}
	return t
}

is_type_untyped :: proc(type: doc.Type) -> bool {
	if type.kind == .Basic {
		flags := transmute(doc.Type_Flags_Basic)type.flags
		return .Untyped in flags
	}
	return false
}

common_prefix :: proc(strs: []string) -> string {
	if len(strs) == 0 {
		return ""
	}
	n := max(int)
	for str in strs {
		n = min(n, len(str))
	}

	prefix := strs[0][:n]
	for str in strs[1:] {
		for len(prefix) != 0 && str[:len(prefix)] != prefix {
			prefix = prefix[:len(prefix)-1]
		}
		if len(prefix) == 0 {
			break
		}
	}
	return prefix
}

recursive_make_directory :: proc(path: string, prefix := "") {
	head, _, tail := strings.partition(path, "/")
	path_to_make := head
	if prefix != "" {
		path_to_make = fmt.tprintf("%s/%s", prefix, head)
	}
	os.make_directory(path_to_make, 0)
	if tail != "" {
		recursive_make_directory(tail, path_to_make)
	}
}


write_html_header :: proc(w: io.Writer, title: string) {
	fmt.wprintf(w, string(#load("header.txt.html")), title)
	io.write(w, #load("header-lower.txt.html"))
}

write_html_footer :: proc(w: io.Writer, include_directory_js: bool) {
	fmt.wprintf(w, "\n")

	io.write(w, #load("footer.txt.html"))

	if false && include_directory_js {
		io.write_string(w, `
<script type="text/javascript">
(function (win, doc) {
	'use strict';
	if (!doc.querySelectorAll || !win.addEventListener) {
		// doesn't cut the mustard.
		return;
	}
	let toggles = doc.querySelectorAll('[aria-controls]');
	for (let i = 0; i < toggles.length; i = i + 1) {
		let toggleID = toggles[i].getAttribute('aria-controls');
		if (doc.getElementById(toggleID)) {
			let togglecontent = doc.getElementById(toggleID);
			togglecontent.setAttribute('aria-hidden', 'true');
			togglecontent.setAttribute('tabindex', '-1');
			toggles[i].setAttribute('aria-expanded', 'false');
		}
	}
	function toggle(ev) {
		ev = ev || win.event;
		var target = ev.target || ev.srcElement;
		if (target.hasAttribute('data-aria-owns')) {
			let toggleIDs = target.getAttribute('data-aria-owns').match(/[^ ]+/g);
			toggleIDs.forEach(toggleID => {
				if (doc.getElementById(toggleID)) {
					ev.preventDefault();
					let togglecontent = doc.getElementById(toggleID);
					if (togglecontent.getAttribute('aria-hidden') == 'true') {
						togglecontent.setAttribute('aria-hidden', 'false');
						target.setAttribute('aria-expanded', 'true');
						if (target.tagName == 'A') {
							togglecontent.focus();
						}
					} else {
						togglecontent.setAttribute('aria-hidden', 'true');
						target.setAttribute('aria-expanded', 'false');
					}
				}
			})
		}
	}
	doc.addEventListener('click', toggle, false);
}(this, this.document));
</script>`)
	}

	fmt.wprintf(w, "</body>\n</html>\n")
}

main :: proc() {
	if len(os.args) != 2 {
		errorf("expected 1 .odin-doc file")
	}
	data, ok := os.read_entire_file(os.args[1])
	if !ok {
		errorf("unable to read file:", os.args[1])
	}
	err: doc.Reader_Error
	header, err = doc.read_from_bytes(data)
	switch err {
	case .None:
	case .Header_Too_Small:
		errorf("file is too small for the file format")
	case .Invalid_Magic:
		errorf("invalid magic for the file format")
	case .Data_Too_Small:
		errorf("data is too small for the file format")
	case .Invalid_Version:
		errorf("invalid file format version")
	}
	files    = array(header.files)
	pkgs     = array(header.pkgs)
	entities = array(header.entities)
	types    = array(header.types)

	{
		fullpaths: [dynamic]string
		defer delete(fullpaths)

		for pkg in pkgs[1:] {
			append(&fullpaths, str(pkg.fullpath))
		}
		path_prefix := common_prefix(fullpaths[:])

		pkgs_to_use = make(map[string]^doc.Pkg)
		fullpath_loop: for fullpath, i in fullpaths {
			path := strings.trim_prefix(fullpath, path_prefix)
			if !strings.has_prefix(path, "core/") {
				continue fullpath_loop
			}
			pkg := &pkgs[i+1]
			if len(array(pkg.entities)) == 0 {
				continue fullpath_loop
			}
			trimmed_path := strings.trim_prefix(path, "core/")
			if strings.has_prefix(trimmed_path, "sys") {
				continue fullpath_loop
			}

			pkgs_to_use[trimmed_path] = pkg
		}
		for path, pkg in pkgs_to_use {
			pkg_to_path[pkg] = path
		}
	}

	b := strings.make_builder()
	defer strings.destroy_builder(&b)
	w := strings.to_writer(&b)

	{
		strings.reset_builder(&b)
		write_html_header(w, "Packages - pkg.odin-lang.org")
		write_home_page(w)
		write_html_footer(w, true)
		os.write_entire_file("index.html", b.buf[:])
	}

	{
		strings.reset_builder(&b)
		write_html_header(w, "core library - pkg.odin-lang.org")
		write_core_directory(w)
		write_html_footer(w, true)
		os.make_directory("core", 0)
		os.write_entire_file("core/index.html", b.buf[:])
	}

	for path, pkg in pkgs_to_use {
		strings.reset_builder(&b)
		write_html_header(w, fmt.tprintf("package %s - pkg.odin-lang.org", path))
		write_pkg(w, path, pkg)
		write_html_footer(w, false)
		recursive_make_directory(path, "core")
		os.write_entire_file(fmt.tprintf("core/%s/index.html", path), b.buf[:])
	}
}

write_home_page :: proc(w: io.Writer) {
	fmt.wprintln(w, `<div class="row odin-main">`)
	defer fmt.wprintln(w, `</div>`)

	{
		fmt.wprintln(w, `<nav class="col-lg-2 odin-sidebar-border navbar-light">`)
		defer fmt.wprintln(w, `</nav>`)
		fmt.wprintln(w, `<div class="sticky-top odin-below-navbar py-3">`)
		defer fmt.wprintln(w, `</div>`)

		fmt.wprintln(w, `<ul class="nav nav-pills d-flex flex-column">`)
		fmt.wprintln(w, `<li class="nav-item"><a class="nav-link" href="/core">Core Library</a></li>`)
		fmt.wprintln(w, `<li class="nav-item"><a class="nav-link" href="#">Vendor Library</a></li>`)
		fmt.wprintln(w, `</ul>`)

	}


	fmt.wprintln(w, `<article class="col-lg-8 p-4">`)
	defer fmt.wprintln(w, `</article>`)

	fmt.wprintln(w, "<article><header>")
	fmt.wprintln(w, "<h1>Odin Packages</h1>")
	fmt.wprintln(w, "</header></article>")
	fmt.wprintln(w, "<div>")
	defer fmt.wprintln(w, "</div>")

	fmt.wprintln(w, `<div class="mt-5">`)
	fmt.wprintln(w, `<a href="/core" class="link-primary text-decoration-node"><h3>Core Library Collection</h3></a>`)
	fmt.wprintln(w, `<p>Documentation for all the packages part of the <code>core</code> library collection.</p>`)
	fmt.wprintln(w, `</div>`)

	fmt.wprintln(w, `<div class="mt-5">`)
	fmt.wprintln(w, `<a href="#" class="link-primary text-decoration-node"><h3>Vendor Library Collection</h3></a>`)
	fmt.wprintln(w, `<p>Documentation for all the packages part of the <code>vendor</code> library collection.</p>`)
	fmt.wprintln(w, `<p><em>Coming Soon.</em></p>`)
	fmt.wprintln(w, `</div>`)



}



Dir_Node :: struct {
	dir: string,
	path: string,
	name: string,
	pkg: ^doc.Pkg,
	children: [dynamic]^Dir_Node,
}

generate_directory_tree :: proc() -> (root: ^Dir_Node) {
	sort_tree :: proc(node: ^Dir_Node) {
		slice.sort_by_key(node.children[:], proc(node: ^Dir_Node) -> string {return node.name})
		for child in node.children {
			sort_tree(child)
		}
	}
	root = new(Dir_Node)
	root.children = make([dynamic]^Dir_Node)
	children := make([dynamic]^Dir_Node)
	for path, pkg in pkgs_to_use {
		dir, _, inner := strings.partition(path, "/")
		if inner == "" {
			node := new_clone(Dir_Node{
				dir  = dir,
				name = dir,
				path = path,
				pkg  = pkg,
			})
			append(&root.children, node)
		} else {
			node := new_clone(Dir_Node{
				dir  = dir,
				name = inner,
				path = path,
				pkg  = pkg,
			})
			append(&children, node)
		}
	}
	child_loop: for child in children {
		dir, _, inner := strings.partition(child.path, "/")
		for node in root.children {
			if node.dir == dir {
				append(&node.children, child)
				continue child_loop
			}
		}
		parent := new_clone(Dir_Node{
			dir  = dir,
			name = dir,
			path = dir,
			pkg  = nil,
		})
		append(&root.children, parent)
		append(&parent.children, child)
	}

	sort_tree(root)

	return
}

write_core_directory :: proc(w: io.Writer) {
	root := generate_directory_tree()

	fmt.wprintln(w, `<div class="row odin-main">`)
	defer fmt.wprintln(w, `</div>`)
	{
		fmt.wprintln(w, `<article class="col-lg-12 p-4">`)
		fmt.wprintln(w, `<header class="collection-header">`)
		fmt.wprintln(w, "<h1>Core Library Collection</h1>")
		fmt.wprintln(w, "<ul>")
		fmt.wprintf(w, "<li>License: <a href=\"{0:s}\">BSD-3-Clause</a></li>\n", GITHUB_LICENSE_URL)
		fmt.wprintf(w, "<li>Repository: <a href=\"{0:s}\">{0:s}</a></li>\n", GITHUB_CORE_URL)
		fmt.wprintln(w, "</ul>")
		fmt.wprintln(w, "</header>")
		fmt.wprintln(w, "</article>")
		fmt.wprintln(w, `<hr class="collection-hr">`)
	}
	fmt.wprintln(w, `<article class="col-lg-12 p-4">`)
	defer fmt.wprintln(w, `</article>`)

	fmt.wprintln(w, "<header>")
	fmt.wprintln(w, `<h2><i class="bi bi-folder"></i>Directories</h2>`)
	fmt.wprintln(w, "</header>")

	fmt.wprintln(w, "<div>")
	fmt.wprintln(w, "\t<table class=\"doc-directory mt-4 mb-4\">")
	fmt.wprintln(w, "\t\t<tbody>")

	for dir in root.children {
		if len(dir.children) != 0 {
			fmt.wprint(w, `<tr aria-controls="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", str(child.pkg.name))
			}
			fmt.wprint(w, `" class="directory-pkg"><td class="pkg-line pkg-name" data-aria-owns="`)
			for child in dir.children {
				fmt.wprintf(w, "pkg-%s ", str(child.pkg.name))
			}
			fmt.wprintf(w, `" id="pkg-%s">`, dir.dir)
		} else {
			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg"><td class="pkg-name">`, dir.dir)
		}

		if dir.pkg != nil {
			fmt.wprintf(w, `<a href="%s/%s">%s</a>`, BASE_CORE_URL, dir.path, dir.name)
		} else {
			fmt.wprintf(w, "%s", dir.name)
		}
		io.write_string(w, `</td>`)
		io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
		if dir.pkg != nil {
			line_doc, _, _ := strings.partition(str(dir.pkg.docs), "\n")
			line_doc = strings.trim_space(line_doc)
			if line_doc != "" {
				write_doc_line(w, line_doc)
			}
		}
		io.write_string(w, `</td>`)
		fmt.wprintf(w, "</tr>\n")

		for child in dir.children {
			assert(child.pkg != nil)
			fmt.wprintf(w, `<tr id="pkg-%s" class="directory-pkg directory-child"><td class="pkg-line pkg-name">`, str(child.pkg.name))
			fmt.wprintf(w, `<a href="%s/%s/">%s</a>`, BASE_CORE_URL, child.path, child.name)
			io.write_string(w, `</td>`)

			line_doc, _, _ := strings.partition(str(child.pkg.docs), "\n")
			line_doc = strings.trim_space(line_doc)
			io.write_string(w, `<td class="pkg-line pkg-line-doc">`)
			if line_doc != "" {
				write_doc_line(w, line_doc)
			}
			io.write_string(w, `</td>`)

			fmt.wprintf(w, "</td>")
			fmt.wprintf(w, "</tr>\n")
		}
	}

	fmt.wprintln(w, "\t\t</tbody>")
	fmt.wprintln(w, "\t</table>")
	fmt.wprintln(w, "</div>")
}

is_entity_blank :: proc(e: doc.Entity_Index) -> bool {
	name := str(entities[e].name)
	return name == ""
}

write_where_clauses :: proc(w: io.Writer, where_clauses: []doc.String) {
	if len(where_clauses) != 0 {
		io.write_string(w, " where ")
		for clause, i in where_clauses {
			if i > 0 {
				io.write_string(w, ", ")
			}
			io.write_string(w, str(clause))
		}
	}
}


Write_Type_Flag :: enum {
	Is_Results,
	Variadic,
	Allow_Indent,
	Poly_Names,
}
Write_Type_Flags :: distinct bit_set[Write_Type_Flag]
Type_Writer :: struct {
	w:      io.Writer,
	pkg:    doc.Pkg_Index,
	indent: int,
	generic_scope: map[string]bool,
}

write_type :: proc(using writer: ^Type_Writer, type: doc.Type, flags: Write_Type_Flags) {
	write_param_entity :: proc(using writer: ^Type_Writer, e, next_entity: ^doc.Entity, flags: Write_Type_Flags, name_width := 0) {
		name := str(e.name)

		write_padding :: proc(w: io.Writer, name: string, name_width: int) {
			for _ in 0..<name_width-len(name) {
				io.write_byte(w, ' ')
			}
		}

		if .Param_Using     in e.flags { io.write_string(w, "using ")      }
		if .Param_Const     in e.flags { io.write_string(w, "#const ")     }
		if .Param_Auto_Cast in e.flags { io.write_string(w, "#auto_cast ") }
		if .Param_CVararg   in e.flags { io.write_string(w, "#c_vararg ")  }
		if .Param_No_Alias  in e.flags { io.write_string(w, "#no_alias ")  }
		if .Param_Any_Int   in e.flags { io.write_string(w, "#any_int ")   }

		init_string := str(e.init_string)
		switch {
		case init_string == "#caller_location":
			assert(name != "")
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Source_Code_Location">`, BASE_CORE_URL)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case strings.has_prefix(init_string, "context."):
			io.write_string(w, name)
			io.write_string(w, " := ")
			fmt.wprintf(w, `<a href="%s/runtime/#Context">`, BASE_CORE_URL)
			io.write_string(w, init_string)
			io.write_string(w, `</a>`)
		case:
			the_type := types[e.type]
			type_flags := flags - {.Is_Results}
			if .Param_Ellipsis in e.flags {
				type_flags += {.Variadic}
			}

			#partial switch e.kind {
			case .Constant:
				assert(name != "")
				io.write_byte(w, '$')
				io.write_string(w, name)
				if name != "" && init_string == "" && next_entity != nil && e.field_group_index >= 0 {
					if e.field_group_index == next_entity.field_group_index && e.type == next_entity.type {
						return
					}
				}

				generic_scope[name] = true
				if !is_type_untyped(the_type) {
					io.write_string(w, ": ")
					write_padding(w, name, name_width)
					write_type(writer, the_type, type_flags)
					io.write_string(w, " = ")
					io.write_string(w, init_string)
				} else {
					io.write_string(w, " := ")
					io.write_string(w, init_string)
				}
				return

			case .Variable:
				if name != "" && init_string == "" && next_entity != nil && e.field_group_index >= 0 {
					if e.field_group_index == next_entity.field_group_index && e.type == next_entity.type {
						io.write_string(w, name)
						return
					}
				}

				if name != "" {
					io.write_string(w, name)
					io.write_string(w, ": ")
					write_padding(w, name, name_width)
				}
				write_type(writer, the_type, type_flags)
			case .Type_Name:
				io.write_byte(w, '$')
				io.write_string(w, name)
				generic_scope[name] = true
				io.write_string(w, ": ")
				write_padding(w, name, name_width)
				if the_type.kind == .Generic {
					io.write_string(w, "typeid")
					if ts := array(the_type.types); len(ts) == 1 {
						io.write_byte(w, '/')
						write_type(writer, types[ts[0]], type_flags)
					}
				} else {
					write_type(writer, the_type, type_flags)
				}
			}

			if init_string != "" {
				io.write_string(w, " = ")
				io.write_string(w, init_string)
			}
		}
	}
	write_poly_params :: proc(using writer: ^Type_Writer, type: doc.Type, flags: Write_Type_Flags) {
		if type.polymorphic_params != 0 {
			io.write_byte(w, '(')
			write_type(writer, types[type.polymorphic_params], flags+{.Poly_Names})
			io.write_byte(w, ')')
		}

		write_where_clauses(w, array(type.where_clauses))
	}
	do_indent :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags) {
		if .Allow_Indent not_in flags {
			return
		}
		for _ in 0..<indent {
			io.write_byte(w, '\t')
		}
	}
	do_newline :: proc(using writer: ^Type_Writer, flags: Write_Type_Flags) {
		if .Allow_Indent in flags {
			io.write_byte(w, '\n')
		}
	}
	calc_name_width :: proc(type_entities: []doc.Entity_Index) -> (name_width: int) {
		for entity_index in type_entities {
			e := &entities[entity_index]
			name := str(e.name)
			name_width = max(len(name), name_width)
		}
		return
	}


	type_entities := array(type.entities)
	type_types := array(type.types)
	switch type.kind {
	case .Invalid:
		// ignore
	case .Basic:
		type_flags := transmute(doc.Type_Flags_Basic)type.flags
		if is_type_untyped(type) {
			io.write_string(w, str(type.name))
		} else {
			fmt.wprintf(w, `<a href="">%s</a>`, str(type.name))
		}
	case .Named:
		e := entities[type_entities[0]]
		name := str(type.name)
		tn_pkg := files[e.pos.file].pkg

		if tn_pkg != pkg {
			fmt.wprintf(w, `%s.`, str(pkgs[tn_pkg].name))
		}
		if .Private in e.flags {
			io.write_string(w, name)
		} else if n := strings.contains_rune(name, '('); n >= 0 {
			fmt.wprintf(w, `<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`, pkg_to_path[&pkgs[tn_pkg]], name[:n], BASE_CORE_URL)
			io.write_string(w, name[n:])
		} else {
			fmt.wprintf(w, `<a class="code-typename" href="{2:s}/{0:s}/#{1:s}">{1:s}</a>`, pkg_to_path[&pkgs[tn_pkg]], name, BASE_CORE_URL)
		}
	case .Generic:
		name := str(type.name)
		if name not_in generic_scope {
			io.write_byte(w, '$')
		}
		io.write_string(w, name)
		if name not_in generic_scope && len(array(type.types)) == 1 {
			io.write_byte(w, '/')
			write_type(writer, types[type_types[0]], flags)
		}
	case .Pointer:
		io.write_byte(w, '^')
		write_type(writer, types[type_types[0]], flags)
	case .Array:
		assert(type.elem_count_len == 1)
		io.write_byte(w, '[')
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
		write_type(writer, types[type_types[0]], flags)
	case .Enumerated_Array:
		io.write_byte(w, '[')
		write_type(writer, types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, types[type_types[1]], flags)
	case .Slice:
		if .Variadic in flags {
			io.write_string(w, "..")
		} else {
			io.write_string(w, "[]")
		}
		write_type(writer, types[type_types[0]], flags - {.Variadic})
	case .Dynamic_Array:
		io.write_string(w, "[dynamic]")
		write_type(writer, types[type_types[0]], flags)
	case .Map:
		io.write_string(w, "map[")
		write_type(writer, types[type_types[0]], flags)
		io.write_byte(w, ']')
		write_type(writer, types[type_types[1]], flags)
	case .Struct:
		type_flags := transmute(doc.Type_Flags_Struct)type.flags
		io.write_string(w, "struct")
		write_poly_params(writer, type, flags)
		if .Packed in type_flags { io.write_string(w, " #packed") }
		if .Raw_Union in type_flags { io.write_string(w, " #raw_union") }
		if custom_align := str(type.custom_align); custom_align != "" {
			io.write_string(w, " #align")
			io.write_string(w, custom_align)
		}
		io.write_string(w, " {")

		tags := array(type.tags)

		if len(type_entities) != 0 {
			do_newline(writer, flags)
			indent += 1
			name_width := calc_name_width(type_entities)

			for entity_index, i in type_entities {
				e := &entities[entity_index]
				next_entity: ^doc.Entity = nil
				if i+1 < len(type_entities) {
					next_entity = &entities[type_entities[i+1]]
				}
				do_indent(writer, flags)
				write_param_entity(writer, e, next_entity, flags, name_width)

				if tag := str(tags[i]); tag != "" {
					io.write_byte(w, ' ')
					io.write_quoted_string(w, tag)
				}

				io.write_byte(w, ',')
				do_newline(writer, flags)
			}
			indent -= 1
			do_indent(writer, flags)
		}
		io.write_string(w, "}")
	case .Union:
		type_flags := transmute(doc.Type_Flags_Union)type.flags
		io.write_string(w, "union")
		write_poly_params(writer, type, flags)
		if .No_Nil in type_flags { io.write_string(w, " #no_nil") }
		if .Maybe in type_flags { io.write_string(w, " #maybe") }
		if custom_align := str(type.custom_align); custom_align != "" {
			io.write_string(w, " #align")
			io.write_string(w, custom_align)
		}
		io.write_string(w, " {")
		if len(type_types) > 1 {
			do_newline(writer, flags)
			indent += 1
			for type_index in type_types {
				do_indent(writer, flags)
				write_type(writer, types[type_index], flags)
				io.write_string(w, ", ")
				do_newline(writer, flags)
			}
			indent -= 1
			do_indent(writer, flags)
		}
		io.write_string(w, "}")
	case .Enum:
		io.write_string(w, "enum")
		if len(type_types) != 0 {
			io.write_byte(w, ' ')
			write_type(writer, types[type_types[0]], flags)
		}
		io.write_string(w, " {")
		do_newline(writer, flags)
		indent += 1

		name_width := calc_name_width(type_entities)

		for entity_index in type_entities {
			e := &entities[entity_index]

			name := str(e.name)
			do_indent(writer, flags)
			io.write_string(w, name)

			if init_string := str(e.init_string); init_string != "" {
				for _ in 0..<name_width-len(name) {
					io.write_byte(w, ' ')
				}
				io.write_string(w, " = ")
				io.write_string(w, init_string)
			}
			io.write_string(w, ", ")
			do_newline(writer, flags)
		}
		indent -= 1
		do_indent(writer, flags)
		io.write_string(w, "}")
	case .Tuple:
		if len(type_entities) == 0 {
			return
		}
		require_parens := (.Is_Results in flags) && (len(type_entities) > 1 || !is_entity_blank(type_entities[0]))
		if require_parens { io.write_byte(w, '(') }
		for entity_index, i in type_entities {
			if i > 0 {
				io.write_string(w, ", ")
			}
			e := &entities[entity_index]
			next_entity: ^doc.Entity = nil
			if i+1 < len(type_entities) {
				next_entity = &entities[type_entities[i+1]]
			}
			write_param_entity(writer, e, next_entity, flags)
		}
		if require_parens { io.write_byte(w, ')') }

	case .Proc:
		type_flags := transmute(doc.Type_Flags_Proc)type.flags
		io.write_string(w, "proc")
		cc := str(type.calling_convention)
		if cc != "" {
			io.write_byte(w, ' ')
			io.write_quoted_string(w, cc)
			io.write_byte(w, ' ')
		}
		params := array(type.types)[0]
		results := array(type.types)[1]
		io.write_byte(w, '(')
		write_type(writer, types[params], flags)
		io.write_byte(w, ')')
		if results != 0 {
			assert(.Diverging not_in type_flags)
			io.write_string(w, " -> ")
			write_type(writer, types[results], flags+{.Is_Results})
		}
		if .Diverging in type_flags {
			io.write_string(w, " -> !")
		}
		if .Optional_Ok in type_flags {
			io.write_string(w, " #optional_ok")
		}

	case .Bit_Set:
		type_flags := transmute(doc.Type_Flags_Bit_Set)type.flags
		io.write_string(w, "bit_set[")
		if .Op_Lt in type_flags {
			io.write_uint(w, uint(type.elem_counts[0]))
			io.write_string(w, "..<")
			io.write_uint(w, uint(type.elem_counts[1]))
		} else if .Op_Lt_Eq in type_flags {
			io.write_uint(w, uint(type.elem_counts[0]))
			io.write_string(w, "..=")
			io.write_uint(w, uint(type.elem_counts[1]))
		} else {
			write_type(writer, types[type_types[0]], flags)
		}
		if .Underlying_Type in type_flags {
			write_type(writer, types[type_types[1]], flags)
		}
		io.write_string(w, "]")
	case .Simd_Vector:
		io.write_string(w, "#simd[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
	case .SOA_Struct_Fixed:
		io.write_string(w, "#soa[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_byte(w, ']')
	case .SOA_Struct_Slice:
		io.write_string(w, "#soa[]")
	case .SOA_Struct_Dynamic:
		io.write_string(w, "#soa[dynamic]")
	case .Relative_Pointer:
		io.write_string(w, "#relative(")
		write_type(writer, types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, types[type_types[0]], flags)
	case .Relative_Slice:
		io.write_string(w, "#relative(")
		write_type(writer, types[type_types[1]], flags)
		io.write_string(w, ") ")
		write_type(writer, types[type_types[0]], flags)
	case .Multi_Pointer:
		io.write_string(w, "[^]")
		write_type(writer, types[type_types[0]], flags)
	case .Matrix:
		io.write_string(w, "matrix[")
		io.write_uint(w, uint(type.elem_counts[0]))
		io.write_string(w, ", ")
		io.write_uint(w, uint(type.elem_counts[1]))
		io.write_string(w, "]")
		write_type(writer, types[type_types[0]], flags)
	}
}

write_doc_line :: proc(w: io.Writer, text: string) {
	text := text
	for len(text) != 0 {
		if strings.count(text, "`") >= 2 {
			n := strings.index_byte(text, '`')
			io.write_string(w, text[:n])
			io.write_string(w, "<code class=\"code-inline\">")
			remaining := text[n+1:]
			m := strings.index_byte(remaining, '`')
			io.write_string(w, remaining[:m])
			io.write_string(w, "</code>")
			text = remaining[m+1:]
		} else {
			io.write_string(w, text)
			return
		}
	}
}

write_docs :: proc(w: io.Writer, pkg: ^doc.Pkg, docs: string) {
	if docs == "" {
		return
	}
	Block_Kind :: enum {
		Paragraph,
		Code,
	}
	Block :: struct {
		kind: Block_Kind,
		lines: []string,
	}

	lines: [dynamic]string
	it := docs
	for line_ in strings.split_iterator(&it, "\n") {
		line := strings.trim_right_space(line_)
		append(&lines, line)
	}

	curr_block_kind := Block_Kind.Paragraph
	start := 0
	blocks: [dynamic]Block

	for line, i in lines {
		text := strings.trim_space(line)
		switch curr_block_kind {
		case .Paragraph:
			if strings.has_prefix(line, "\t") {
				if i-start > 0 {
					append(&blocks, Block{curr_block_kind, lines[start:i]})
				}
				curr_block_kind, start = .Code, i
			} else if text == "" {
				if i-start > 0 {
					append(&blocks, Block{curr_block_kind, lines[start:i]})
				}
				start = i
			}
		case .Code:
			if text == "" || strings.has_prefix(line, "\t") {
				continue
			}

			if i-start > 0 {
				append(&blocks, Block{curr_block_kind, lines[start:i]})
			}
			curr_block_kind, start = .Paragraph, i
		}
	}
	if start < len(lines) {
		if len(lines)-start > 0 {
			append(&blocks, Block{curr_block_kind, lines[start:]})
		}
	}

	for block in &blocks {
		trim_amount := 0
		for trim_amount = 0; trim_amount < len(block.lines); trim_amount += 1 {
			line := block.lines[trim_amount]
			if strings.trim_space(line) != "" {
				break
			}
		}
		block.lines = block.lines[trim_amount:]
	}

	for block, i in blocks {
		if len(block.lines) == 0 {
			continue
		}
		prev_line := ""
		if i > 0 {
			prev_lines := blocks[i-1].lines
			if len(prev_lines) > 0 {
				prev_line = prev_lines[len(prev_lines)-1]
			}
		}
		prev_line = strings.trim_space(prev_line)

		lines := block.lines[:]

		end_line := block.lines[len(lines)-1]
		if block.kind == .Paragraph && i+1 < len(blocks) {
			if strings.has_prefix(end_line, "Example:") && blocks[i+1].kind == .Code {
				lines = lines[:len(lines)-1]
			}
		}

		switch block.kind {
		case .Paragraph:
			io.write_string(w, "<p>")
			for line, line_idx in lines {
				if line_idx > 0 {
					io.write_string(w, "\n")
				}
				io.write_string(w, line)
			}
			io.write_string(w, "</p>\n")
		case .Code:
			all_blank := len(lines) > 0
			for line in lines {
				if strings.trim_space(line) != "" {
					all_blank = false
				}
			}
			if all_blank {
				continue
			}

			if strings.has_prefix(prev_line, "Example:") {
				io.write_string(w, "<details open class=\"code-example\">\n")
				defer io.write_string(w, "</details>\n")
				io.write_string(w, "<summary>Example:</summary>\n")
				io.write_string(w, `<pre><code class="hljs" data-lang="odin">`)
				for line in lines {
					io.write_string(w, strings.trim_prefix(line, "\t"))
					io.write_string(w, "\n")
				}
				io.write_string(w, "</code></pre>\n")
			} else {
				io.write_string(w, "<pre>")
				for line in lines {
					io.write_string(w, strings.trim_prefix(line, "\t"))
					io.write_string(w, "\n")
				}
				io.write_string(w, "</pre>\n")
			}
		}
	}
}

write_pkg :: proc(w: io.Writer, path: string, pkg: ^doc.Pkg) {
	fmt.wprintln(w, `<div class="row odin-main">`)
	defer fmt.wprintln(w, `</div>`)

	fmt.wprintln(w, `<article class="col-lg-9 p-4 documentation odin-article">`)

	{ // breadcrumbs
		fmt.wprintln(w, `<div class="row">`)
		defer fmt.wprintln(w, `</div>`)

		fmt.wprintln(w, `<nav aria-label="breadcrumb">`)
		defer fmt.wprintln(w, `</nav>`)
		io.write_string(w, "<ol class=\"breadcrumb\">\n")
		defer io.write_string(w, "</ol>\n")

		fmt.wprintf(w, `<li class="breadcrumb-item"><a class="breadcrumb-link" href="%s">core</a></li>`, BASE_CORE_URL)

		dirs := strings.split(path, "/")
		for dir, i in dirs {
			url := strings.join(dirs[:i+1], "/")
			short_path := strings.join(dirs[1:i+1], "/")

			a_class := "breadcrumb-link"
			is_curr := i+1 == len(dirs)
			if is_curr {
				io.write_string(w, `<li class="breadcrumb-item active" aria-current="page">`)
			} else {
				io.write_string(w, `<li class="breadcrumb-item">`)
			}

			if !is_curr && (short_path in pkgs_to_use) {
				fmt.wprintf(w, `<a href="%s/%s">%s</a>`, BASE_CORE_URL, url, dir)
			} else {
				io.write_string(w, dir)
			}
			io.write_string(w, "</li>\n")
		}
	}


	fmt.wprintf(w, "<h1>package core:%s</h1>\n", path)
	overview_docs := strings.trim_space(str(pkg.docs))
	if overview_docs != "" {
		fmt.wprintln(w, "<h2>Overview</h2>")
		fmt.wprintln(w, "<div id=\"pkg-overview\">")
		defer fmt.wprintln(w, "</div>")

		write_docs(w, pkg, overview_docs)
	}

	fmt.wprintln(w, `<h2>Index</h2>`)
	fmt.wprintln(w, `<div id="pkg-index">`)
	pkg_procs:       [dynamic]^doc.Entity
	pkg_proc_groups: [dynamic]^doc.Entity
	pkg_types:       [dynamic]^doc.Entity
	pkg_vars:        [dynamic]^doc.Entity
	pkg_consts:      [dynamic]^doc.Entity

	for entity_index in array(pkg.entities) {
		e := &entities[entity_index]
		name := str(e.name)
		if name == "" || name[0] == '_' {
			continue
		}
		switch e.kind {
		case .Invalid, .Import_Name, .Library_Name:
			// ignore
		case .Constant:   append(&pkg_consts, e)
		case .Variable:   append(&pkg_vars, e)
		case .Type_Name:  append(&pkg_types, e)
		case .Procedure:  append(&pkg_procs, e)
		case .Proc_Group: append(&pkg_proc_groups, e)
		}
	}

	entity_key :: proc(e: ^doc.Entity) -> string {
		return str(e.name)
	}

	slice.sort_by_key(pkg_procs[:],       entity_key)
	slice.sort_by_key(pkg_proc_groups[:], entity_key)
	slice.sort_by_key(pkg_types[:],       entity_key)
	slice.sort_by_key(pkg_vars[:],        entity_key)
	slice.sort_by_key(pkg_consts[:],      entity_key)

	write_index :: proc(w: io.Writer, name: string, entities: []^doc.Entity) {
		fmt.wprintln(w, `<div>`)
		defer fmt.wprintln(w, `</div>`)


		fmt.wprintf(w, `<details open class="doc-index" id="doc-index-{0:s}" aria-labelledby="#doc-index-{0:s}-header">`+"\n", name)
		fmt.wprintf(w, `<summary id="#doc-index-{0:s}-header">`+"\n", name)
		io.write_string(w, name)
		fmt.wprintln(w, `</summary>`)
		defer fmt.wprintln(w, `</details>`)

		if len(entities) == 0 {
			io.write_string(w, "<p>This section is empty.</p>\n")
		} else {
			fmt.wprintln(w, "<ul>")
			for e in entities {
				name := str(e.name)
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", name)
			}
			fmt.wprintln(w, "</ul>")
		}
	}

	entity_ordering := [?]struct{name: string, entities: []^doc.Entity} {
		{"Types",            pkg_types[:]},
		{"Constants",        pkg_consts[:]},
		{"Variables",        pkg_vars[:]},
		{"Procedures",       pkg_procs[:]},
		{"Procedure Groups", pkg_proc_groups[:]},
	}


	for eo in entity_ordering {
		write_index(w, eo.name, eo.entities)
	}

	fmt.wprintln(w, "</div>")


	write_entity :: proc(w: io.Writer, e: ^doc.Entity) {
		write_attributes :: proc(w: io.Writer, e: ^doc.Entity) {
			for attr in array(e.attributes) {
				io.write_string(w, "@(")
				name := str(attr.name)
				value := str(attr.value)
				io.write_string(w, name)
				if value != "" {
					io.write_string(w, "=")
					io.write_string(w, value)
				}
				io.write_string(w, ")\n")
			}
		}

		pkg_index := files[e.pos.file].pkg
		pkg := &pkgs[pkg_index]
		writer := &Type_Writer{
			w = w,
			pkg = pkg_index,
		}
		defer delete(writer.generic_scope)

		name := str(e.name)
		path := pkg_to_path[pkg]
		filename := slashpath.base(str(files[e.pos.file].name))
		fmt.wprintf(w, "<h3 id=\"{0:s}\"><span><a class=\"doc-id-link\" href=\"#{0:s}\">{0:s}", name)
		fmt.wprintf(w, "<span class=\"a-hidden\">&nbsp;¶</span></a></span>")
		if e.pos.file != 0 && e.pos.line > 0 {
			src_url := fmt.tprintf("%s/%s/%s#L%d", GITHUB_CORE_URL, path, filename, e.pos.line)
			fmt.wprintf(w, "<div class=\"doc-source\"><a href=\"{0:s}\"><em>Source</em></a></div>", src_url)
		}
		fmt.wprintf(w, "</h3>\n")
		fmt.wprintln(w, `<div>`)

		switch e.kind {
		case .Invalid, .Import_Name, .Library_Name:
			// ignore
		case .Constant:
			fmt.wprint(w, `<pre class="doc-code">`)
			the_type := types[e.type]

			init_string := str(e.init_string)
			assert(init_string != "")

			ignore_type := true
			if the_type.kind == .Basic && is_type_untyped(the_type) {
			} else {
				ignore_type = false
				type_name := str(the_type.name)
				if type_name != "" && strings.has_prefix(init_string, type_name) {
					ignore_type = true
				}
			}

			if ignore_type {
				fmt.wprintf(w, "%s :: ", name)
			} else {
				fmt.wprintf(w, "%s: ", name)
				write_type(writer, the_type, {.Allow_Indent})
				fmt.wprintf(w, " : ")
			}


			io.write_string(w, init_string)
			fmt.wprintln(w, "</pre>")
		case .Variable:
			fmt.wprint(w, `<pre class="doc-code">`)
			write_attributes(w, e)
			fmt.wprintf(w, "%s: ", name)
			write_type(writer, types[e.type], {.Allow_Indent})
			init_string := str(e.init_string)
			if init_string != "" {
				io.write_string(w, " = ")
				io.write_string(w, "…")
			}
			fmt.wprintln(w, "</pre>")

		case .Type_Name:
			fmt.wprint(w, `<pre class="doc-code">`)
			fmt.wprintf(w, "%s :: ", name)
			the_type := types[e.type]
			type_to_print := the_type
			if the_type.kind == .Named && .Type_Alias not_in e.flags {
				if e.pos == entities[array(the_type.entities)[0]].pos {
					bt := base_type(the_type)
					#partial switch bt.kind {
					case .Struct, .Union, .Proc, .Enum:
						// Okay
					case:
						io.write_string(w, "distinct ")
					}
					type_to_print = bt
				}
			}
			write_type(writer, type_to_print, {.Allow_Indent})
			fmt.wprintln(w, "</pre>")
		case .Procedure:
			fmt.wprint(w, `<pre class="doc-code">`)
			fmt.wprintf(w, "%s :: ", name)
			write_type(writer, types[e.type], nil)
			write_where_clauses(w, array(e.where_clauses))
			fmt.wprint(w, " {…}")
			fmt.wprintln(w, "</pre>")
		case .Proc_Group:
			fmt.wprint(w, `<pre class="doc-code">`)
			fmt.wprintf(w, "%s :: proc{{\n", name)
			for entity_index in array(e.grouped_entities) {
				this_proc := &entities[entity_index]
				this_pkg := files[this_proc.pos.file].pkg
				io.write_byte(w, '\t')
				if this_pkg != pkg_index {
					fmt.wprintf(w, "%s.", str(pkgs[this_pkg].name))
				}
				name := str(this_proc.name)
				fmt.wprintf(w, `<a class="code-procedure" href="{2:s}/{0:s}/#{1:s}">`, pkg_to_path[&pkgs[this_pkg]], name, BASE_CORE_URL)
				io.write_string(w, name)
				io.write_string(w, `</a>`)
				io.write_byte(w, ',')
				io.write_byte(w, '\n')
			}
			fmt.wprintln(w, "}")
			fmt.wprintln(w, "</pre>")

		}
		fmt.wprintln(w, `</div>`)

		the_docs := strings.trim_space(str(e.docs))
		if the_docs != "" {
			fmt.wprintln(w, `<details class="odin-doc-toggle" open>`)
			fmt.wprintln(w, `<summary class="hideme"><span>&nbsp;</span></summary>`)
			write_docs(w, pkg, the_docs)
			fmt.wprintln(w, `</details>`)
		}
	}
	write_entities :: proc(w: io.Writer, title: string, entities: []^doc.Entity) {
		fmt.wprintf(w, "<h2 id=\"pkg-{0:s}\">{0:s}</h2>\n", title)
		fmt.wprintln(w, `<section class="documentation">`)
		if len(entities) == 0 {
			io.write_string(w, "<p>This section is empty.</p>\n")
		} else {
			for e in entities {
				fmt.wprintln(w, `<div class="pkg-entity">`)
				write_entity(w, e)
				fmt.wprintln(w, `</div>`)
			}
		}
		fmt.wprintln(w, "</section>")
	}

	for eo in entity_ordering {
		write_entities(w, eo.name, eo.entities)
	}

	fmt.wprintln(w, `<h2 id="pkg-source-files">Source Files</h2>`)
	fmt.wprintln(w, "<ul>")
	any_hidden := false
	source_file_loop: for file_index in array(pkg.files) {
		file := files[file_index]
		filename := slashpath.base(str(file.name))
		switch {
		case
			strings.has_suffix(filename, "_windows.odin"),
			strings.has_suffix(filename, "_darwin.odin"),
			strings.has_suffix(filename, "_essence.odin"),
			strings.has_suffix(filename, "_freebsd.odin"),
			strings.has_suffix(filename, "_wasi.odin"),
			strings.has_suffix(filename, "_js.odin"),
			strings.has_suffix(filename, "_freestanding.odin"),

			strings.has_suffix(filename, "_amd64.odin"),
			strings.has_suffix(filename, "_i386.odin"),
			strings.has_suffix(filename, "_arch64.odin"),
			strings.has_suffix(filename, "_wasm32.odin"),
			strings.has_suffix(filename, "_wasm64.odin"),
			false:
			any_hidden = true
			continue source_file_loop
		}
		fmt.wprintf(w, `<li><a href="%s/%s/%s">%s</a></li>`, GITHUB_CORE_URL, path, filename, filename)
		fmt.wprintln(w)
	}
	if any_hidden {
		fmt.wprintln(w, "<li><em>(hidden platform specific files)</em></li>")
	}
	fmt.wprintln(w, "</ul>")


	fmt.wprintln(w, `</article>`)
	{
		write_link :: proc(w: io.Writer, id, text: string) {
			fmt.wprintf(w, `<li><a href="#%s">%s</a>`, id, text)
		}

		fmt.wprintln(w, `<div class="col-lg-3 odin-toc-border navbar-light"><div class="sticky-top odin-below-navbar py-3">`)
		fmt.wprintln(w, `<nav id="TableOfContents">`)
		fmt.wprintln(w, `<ul>`)
		if overview_docs != "" {
			write_link(w, "pkg-overview", "Overview")
		}
		for eo in entity_ordering do if len(eo.entities) != 0 {
			fmt.wprintf(w, `<li><a href="#pkg-{0:s}">{0:s}</a>`, eo.name)
			fmt.wprintln(w, `<ul>`)
			for e in eo.entities {
				fmt.wprintf(w, "<li><a href=\"#{0:s}\">{0:s}</a></li>\n", str(e.name))
			}
			fmt.wprintln(w, "</ul>")
			fmt.wprintln(w, "</li>")
		}
		write_link(w, "pkg-source-files", "Source Files")
		fmt.wprintln(w, `</ul>`)
		fmt.wprintln(w, `</nav>`)
		fmt.wprintln(w, `</div></div>`)
	}

}