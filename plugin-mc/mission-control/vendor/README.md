# vendor

Pinned third-party files the cockpit serves itself, so no page reaches the network to render.

marked.min.js — marked 18.0.11, https://cdnjs.cloudflare.com/ajax/libs/marked/18.0.11/lib/marked.umd.min.js, MIT — the reply markdown on the front page; sha256 a7b5c1bdc19be6edf201bc78c1219c2f96a4e92de738e0411fb6e31f738b756b (test_front_talk.sh checks it, and that js/mdsafe.js still renders a reply's HTML, links and images inert)
three.min.js — Three.js r128, https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js, MIT
diff2html.min.js + diff2html.min.css — diff2html 3.4.52, https://cdn.jsdelivr.net/npm/diff2html@3.4.52/bundles/{js/diff2html.min.js,css/diff2html.min.css}, MIT — inlined by dm-gate.sh into proof/<slice>/review.html (cdnjs lists the version but serves no files for it)
