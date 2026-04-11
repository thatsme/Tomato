const LONG_PRESS_MS = 500;
const DRAG_THRESHOLD = 5; // pixels moved before it counts as a drag

const GraphCanvas = {
  mounted() {
    this.dragging = null;
    this.panning = false;
    this.panStart = { x: 0, y: 0 };
    this.viewBox = { x: -50, y: -20, w: 800, h: 600 };
    this.scale = 1;
    this.longPressTimer = null;
    this.longPressFired = false;
    this.mouseDownPos = null;

    this.edgeIndex = {};

    this.updateViewBox();

    // Mouse events
    this.el.addEventListener("mousedown", (e) => this.onMouseDown(e));
    this.el.addEventListener("mousemove", (e) => this.onMouseMove(e));
    this.el.addEventListener("mouseup", (e) => this.onMouseUp(e));
    this.el.addEventListener("mouseleave", (e) => this.onMouseUp(e));

    // Double-click
    this.el.addEventListener("dblclick", (e) => this.onDblClick(e));

    // Also keep right-click for those who have it enabled
    this.el.addEventListener("contextmenu", (e) => this.onContextMenu(e));

    // Trackpad zoom/pan
    this.el.addEventListener("wheel", (e) => this.onWheel(e), { passive: false });

    // Close context menu — but not immediately after it opens
    this.menuJustOpened = false;
    document.addEventListener("mousedown", (e) => {
      if (this.menuJustOpened) return;
      const menu = document.getElementById("ctx-menu");
      if (menu && !menu.contains(e.target)) this.closeContextMenu();
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.closeContextMenu();
    });

    this.buildEdgeIndex();
  },

  updated() {
    this.buildEdgeIndex();
  },

  // --- Edge index ---

  buildEdgeIndex() {
    this.edgeIndex = {};
    this.el.querySelectorAll("#edges path[data-from], #edges path[data-to]").forEach((line) => {
      const from = line.getAttribute("data-from");
      const to = line.getAttribute("data-to");
      if (from) {
        if (!this.edgeIndex[from]) this.edgeIndex[from] = [];
        this.edgeIndex[from].push({ line, role: "from" });
      }
      if (to) {
        if (!this.edgeIndex[to]) this.edgeIndex[to] = [];
        this.edgeIndex[to].push({ line, role: "to" });
      }
    });
  },

  // --- ViewBox ---

  updateViewBox() {
    this.el.setAttribute(
      "viewBox",
      `${this.viewBox.x} ${this.viewBox.y} ${this.viewBox.w} ${this.viewBox.h}`
    );
  },

  onWheel(e) {
    e.preventDefault();

    if (e.ctrlKey || e.metaKey) {
      const zoomFactor = e.deltaY > 0 ? 1.05 : 0.95;
      const pt = this.svgPoint(e);
      this.viewBox.x = pt.x - (pt.x - this.viewBox.x) * zoomFactor;
      this.viewBox.y = pt.y - (pt.y - this.viewBox.y) * zoomFactor;
      this.viewBox.w *= zoomFactor;
      this.viewBox.h *= zoomFactor;
      this.scale *= zoomFactor;
    } else {
      this.viewBox.x += e.deltaX * this.scale;
      this.viewBox.y += e.deltaY * this.scale;
    }

    this.updateViewBox();
  },

  // --- Mouse events ---

  onMouseDown(e) {
    this.cancelLongPress();
    this.longPressFired = false;
    this.mouseDownPos = { x: e.clientX, y: e.clientY };

    const nodeGroup = e.target.closest(".graph-node") || e.target.closest(".oodn-node");
    const edgeLine = e.target.closest("path[data-edge-id]");

    if (nodeGroup) {
      e.preventDefault();

      const nodeId = nodeGroup.dataset.nodeId;
      const nodeType = nodeGroup.dataset.nodeType;
      const nodeName = nodeGroup.dataset.nodeName;

      // Ctrl+click (or Cmd+click on Mac) — open content editor for leaf nodes
      if ((e.ctrlKey || e.metaKey) && nodeType === "leaf") {
        this.pushEvent("edit_node_content", { "node-id": nodeId });
        return;
      }

      const transform = nodeGroup.getAttribute("transform");
      const match = transform.match(/translate\(([^,]+),\s*([^)]+)\)/);
      if (!match) return;

      const currentX = parseFloat(match[1]);
      const currentY = parseFloat(match[2]);
      const pt = this.svgPoint(e);

      this.dragging = {
        nodeId,
        nodeType,
        nodeName,
        element: nodeGroup,
        startX: currentX,
        startY: currentY,
        offsetX: pt.x - currentX,
        offsetY: pt.y - currentY,
        hasMoved: false,
      };

      // Start long-press timer
      this.longPressTimer = setTimeout(() => {
        if (this.dragging && !this.dragging.hasMoved) {
          this.longPressFired = true;
          this.showNodeMenu(e.clientX, e.clientY, nodeId, nodeType, nodeName);
          this.dragging = null;
        }
      }, LONG_PRESS_MS);

    } else if (edgeLine) {
      // Long-press on edge
      const edgeId = edgeLine.getAttribute("data-edge-id");
      this.longPressTimer = setTimeout(() => {
        this.longPressFired = true;
        this.showEdgeMenu(e.clientX, e.clientY, edgeId);
      }, LONG_PRESS_MS);

    } else if (e.button === 0) {
      // Long-press on empty canvas
      const pt = this.svgPoint(e);
      const svgX = Math.round(pt.x);
      const svgY = Math.round(pt.y);

      this.longPressTimer = setTimeout(() => {
        if (!this.panning || !this.panHasMoved) {
          this.longPressFired = true;
          this.showCanvasMenu(e.clientX, e.clientY, svgX, svgY);
          this.panning = false;
        }
      }, LONG_PRESS_MS);

      this.panning = true;
      this.panHasMoved = false;
      this.panStart = { x: e.clientX, y: e.clientY };
    }
  },

  onMouseMove(e) {
    // Check if mouse moved beyond threshold — cancel long press if so
    if (this.mouseDownPos) {
      const dx = Math.abs(e.clientX - this.mouseDownPos.x);
      const dy = Math.abs(e.clientY - this.mouseDownPos.y);
      if (dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD) {
        this.cancelLongPress();
      }
    }

    if (this.dragging) {
      e.preventDefault();
      const pt = this.svgPoint(e);
      const x = Math.round(pt.x - this.dragging.offsetX);
      const y = Math.round(pt.y - this.dragging.offsetY);

      this.dragging.element.setAttribute("transform", `translate(${x}, ${y})`);
      this.dragging.currentX = x;
      this.dragging.currentY = y;
      this.dragging.hasMoved = true;

      this.updateEdgePositions(this.dragging.nodeId, x, y);
    } else if (this.panning) {
      const dx = (e.clientX - this.panStart.x) * this.scale;
      const dy = (e.clientY - this.panStart.y) * this.scale;

      if (Math.abs(dx) > 1 || Math.abs(dy) > 1) {
        this.panHasMoved = true;
      }

      this.viewBox.x -= dx;
      this.viewBox.y -= dy;
      this.panStart = { x: e.clientX, y: e.clientY };
      this.updateViewBox();
    }
  },

  onMouseUp(e) {
    this.cancelLongPress();

    if (this.dragging) {
      const { nodeId, currentX, currentY, startX, startY, hasMoved } = this.dragging;

      if (hasMoved && currentX !== undefined) {
        if (nodeId === "oodn") {
          this.pushEvent("oodn_moved", { x: currentX, y: currentY });
        } else {
          this.pushEvent("node_moved", { node_id: nodeId, x: currentX, y: currentY });
        }
      }

      this.dragging = null;
    }

    this.panning = false;
    this.mouseDownPos = null;
  },

  cancelLongPress() {
    if (this.longPressTimer) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = null;
    }
  },

  // --- Double-click ---

  onDblClick(e) {
    if (this.longPressFired) {
      this.longPressFired = false;
      return;
    }

    const nodeGroup = e.target.closest(".graph-node") || e.target.closest(".oodn-node");
    if (!nodeGroup) return;

    e.preventDefault();

    const nodeId = nodeGroup.dataset.nodeId;
    const nodeType = nodeGroup.dataset.nodeType;

    if (nodeType === "oodn") {
      this.pushEvent("select_oodn", {});
    } else if (nodeType === "gateway") {
      this.pushEvent("enter_gateway", { "node-id": nodeId });
    } else if (nodeType === "leaf") {
      this.pushEvent("edit_node_content", { "node-id": nodeId });
    }
  },

  // --- Context menu (right-click fallback) ---

  onContextMenu(e) {
    e.preventDefault();
    this.closeContextMenu();

    const nodeGroup = e.target.closest(".graph-node");
    const edgeLine = e.target.closest("path[data-edge-id]");

    if (nodeGroup) {
      const { nodeId, nodeType, nodeName } = nodeGroup.dataset;
      this.showNodeMenu(e.clientX, e.clientY, nodeId, nodeType, nodeName);
    } else if (edgeLine) {
      this.showEdgeMenu(e.clientX, e.clientY, edgeLine.getAttribute("data-edge-id"));
    } else {
      const pt = this.svgPoint(e);
      this.showCanvasMenu(e.clientX, e.clientY, Math.round(pt.x), Math.round(pt.y));
    }
  },

  // --- Menu builders ---

  showNodeMenu(clientX, clientY, nodeId, nodeType, nodeName) {
    this.closeContextMenu();

    const items = [];

    // --- Primary actions by type ---
    if (nodeType === "leaf") {
      items.push({ label: "Edit content", icon: "pencil", event: "edit_node_content", params: { "node-id": nodeId } });
    }

    if (nodeType === "gateway") {
      items.push({ label: "Enter subgraph", icon: "arrow-down", event: "enter_gateway", params: { "node-id": nodeId } });
    }

    items.push({ type: "divider" });

    // --- Connectivity ---
    items.push({ label: "Connect from here...", icon: "arrow-right", event: "start_connect", params: { "node-id": nodeId } });
    items.push({ label: "Connect to here...", icon: "arrow-left", event: "start_connect_to", params: { "node-id": nodeId } });

    items.push({ type: "divider" });

    // --- Edit actions ---
    items.push({ label: "Rename", icon: "tag", event: "start_rename", params: { "node-id": nodeId } });

    if (nodeType !== "input" && nodeType !== "output") {
      items.push({ label: "Duplicate", icon: "copy", event: "duplicate_node", params: { "node-id": nodeId } });
    }

    // --- Danger zone ---
    if (nodeType !== "input" && nodeType !== "output") {
      items.push({ type: "divider" });
      items.push({ label: "Disconnect all", icon: "unlink", event: "disconnect_node", params: { "node-id": nodeId }, danger: true });
      items.push({ label: "Delete", icon: "trash", event: "delete_node", params: { "node-id": nodeId }, danger: true });
    }

    this.renderMenu(clientX, clientY, nodeName || "Node", nodeType, items);
  },

  showEdgeMenu(clientX, clientY, edgeId) {
    this.closeContextMenu();
    this.renderMenu(clientX, clientY, "Edge", null, [
      { label: "Reverse direction", icon: "swap", event: "reverse_edge", params: { "edge-id": edgeId } },
      { type: "divider" },
      { label: "Delete edge", icon: "trash", event: "delete_edge", params: { "edge-id": edgeId }, danger: true },
    ]);
  },

  showCanvasMenu(clientX, clientY, svgX, svgY) {
    this.closeContextMenu();
    this.renderMenu(clientX, clientY, "Canvas", null, [
      { label: "Add node from template", icon: "plus", event: "show_template_picker", params: {} },
      { label: "Add gateway", icon: "folder-plus", event: "add_node_at", params: { type: "gateway", x: svgX, y: svgY } },
      { type: "divider" },
      { label: "Fit to view", icon: "fit", event: "fit_to_view", params: {} },
      { label: "Reset zoom", icon: "zoom", event: "reset_zoom", params: {} },
    ]);
  },

  renderMenu(x, y, title, subtitle, items) {
    const ICONS = {
      "pencil":      "M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z",
      "arrow-down":  "M19.5 13.5L12 21m0 0l-7.5-7.5M12 21V3",
      "arrow-right": "M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3",
      "arrow-left":  "M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18",
      "tag":         "M9.568 3H5.25A2.25 2.25 0 003 5.25v4.318c0 .597.237 1.17.659 1.591l9.581 9.581c.699.699 1.78.872 2.607.33a18.095 18.095 0 005.223-5.223c.542-.827.369-1.908-.33-2.607L11.16 3.66A2.25 2.25 0 009.568 3z",
      "copy":        "M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 01-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 011.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 00-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 01-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 00-3.375-3.375h-1.5a1.125 1.125 0 01-1.125-1.125v-1.5a3.375 3.375 0 00-3.375-3.375H9.75",
      "unlink":      "M13.19 8.688a4.5 4.5 0 011.242 7.244l-4.5 4.5a4.5 4.5 0 01-6.364-6.364l1.757-1.757m9.553-5.553L18.75 3.22a4.5 4.5 0 016.364 6.364l-4.5 4.5a4.5 4.5 0 01-7.244-1.242",
      "trash":       "M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0",
      "swap":        "M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5",
      "plus":        "M12 4.5v15m7.5-7.5h-15",
      "folder-plus": "M12 10.5v6m3-3H9m4.06-7.19l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z",
      "fit":         "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15",
      "zoom":        "M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z",
    };

    function svgIcon(name) {
      const path = ICONS[name];
      if (!path) return "";
      return `<svg class="w-4 h-4 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="${path}"/></svg>`;
    }

    const TYPE_COLORS = {
      input: "badge-success",
      output: "badge-error",
      leaf: "badge-info",
      gateway: "badge-secondary",
    };

    const menu = document.createElement("div");
    menu.id = "ctx-menu";
    menu.className = "fixed z-50 shadow-xl rounded-lg border border-base-300 bg-base-100 py-1 min-w-[200px] text-sm";
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;

    // Title row with optional type badge
    const titleRow = document.createElement("div");
    titleRow.className = "px-3 py-2 flex items-center gap-2 border-b border-base-300 mb-1";
    titleRow.innerHTML = `<span class="font-semibold truncate">${title}</span>`;
    if (subtitle) {
      titleRow.innerHTML += `<span class="badge badge-xs ${TYPE_COLORS[subtitle] || ""} ml-auto">${subtitle}</span>`;
    }
    menu.appendChild(titleRow);

    items.forEach((item) => {
      if (item.type === "divider") {
        const hr = document.createElement("hr");
        hr.className = "border-base-300 my-1";
        menu.appendChild(hr);
        return;
      }

      const btn = document.createElement("button");
      btn.className = `flex items-center gap-2 w-full text-left px-3 py-1.5 hover:bg-base-200 cursor-pointer transition-colors ${item.danger ? "text-error hover:bg-error/10" : ""}`;
      btn.innerHTML = `${svgIcon(item.icon)}<span>${item.label}</span>`;
      btn.addEventListener("click", (e) => {
        e.stopPropagation();

        // Handle local-only actions
        if (item.event === "fit_to_view") {
          this.fitToView();
        } else if (item.event === "reset_zoom") {
          this.resetZoom();
        } else {
          this.pushEvent(item.event, item.params);
        }

        this.closeContextMenu();
      });
      menu.appendChild(btn);
    });

    document.body.appendChild(menu);
    const rect = menu.getBoundingClientRect();
    if (rect.right > window.innerWidth) menu.style.left = `${x - rect.width}px`;
    if (rect.bottom > window.innerHeight) menu.style.top = `${y - rect.height}px`;

    // Prevent the mouseup/click from immediately closing the menu
    this.menuJustOpened = true;
    setTimeout(() => { this.menuJustOpened = false; }, 300);
  },

  closeContextMenu() {
    const existing = document.getElementById("ctx-menu");
    if (existing) existing.remove();
  },

  // --- Edge position updates during drag ---

  updateEdgePositions(nodeId, x, y) {
    const entries = this.edgeIndex[nodeId];
    if (!entries) return;

    entries.forEach(({ line, role }) => {
      // Edges are now <path> elements with Bezier curves
      // from = right side (x+60, y), to = left side (x-60, y)
      if (role === "from") {
        this.updateBezierFrom(line, x + 60, y);
      } else {
        this.updateBezierTo(line, x - 60, y);
      }
    });
  },

  updateBezierFrom(path, x1, y1) {
    const d = path.getAttribute("d");
    const match = d.match(/M [^ ]+ [^ ]+ C [^ ]+ [^ ]+, [^ ]+ [^ ]+, ([^ ]+) ([^ ]+)/);
    if (!match) return;
    const x2 = parseFloat(match[1]);
    const y2 = parseFloat(match[2]);
    const dx = Math.abs(x2 - x1);
    const offset = Math.max(dx * 0.5, 80);
    path.setAttribute("d", `M ${x1} ${y1} C ${x1 + offset} ${y1}, ${x2 - offset} ${y2}, ${x2} ${y2}`);
  },

  updateBezierTo(path, x2, y2) {
    const d = path.getAttribute("d");
    const match = d.match(/M ([^ ]+) ([^ ]+) C/);
    if (!match) return;
    const x1 = parseFloat(match[1]);
    const y1 = parseFloat(match[2]);
    const dx = Math.abs(x2 - x1);
    const offset = Math.max(dx * 0.5, 80);
    path.setAttribute("d", `M ${x1} ${y1} C ${x1 + offset} ${y1}, ${x2 - offset} ${y2}, ${x2} ${y2}`);
  },

  // --- View controls ---

  fitToView() {
    const nodes = this.el.querySelectorAll(".graph-node");
    if (nodes.length === 0) return;

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach((n) => {
      const t = n.getAttribute("transform");
      const m = t.match(/translate\(([^,]+),\s*([^)]+)\)/);
      if (!m) return;
      const x = parseFloat(m[1]);
      const y = parseFloat(m[2]);
      minX = Math.min(minX, x - 80);
      minY = Math.min(minY, y - 40);
      maxX = Math.max(maxX, x + 80);
      maxY = Math.max(maxY, y + 40);
    });

    const padding = 60;
    this.viewBox.x = minX - padding;
    this.viewBox.y = minY - padding;
    this.viewBox.w = (maxX - minX) + padding * 2;
    this.viewBox.h = (maxY - minY) + padding * 2;
    this.scale = this.viewBox.w / this.el.clientWidth;
    this.updateViewBox();
  },

  resetZoom() {
    this.viewBox = { x: -50, y: -20, w: 800, h: 600 };
    this.scale = 1;
    this.updateViewBox();
  },

  // --- Helpers ---

  svgPoint(e) {
    const svg = this.el;
    const pt = svg.createSVGPoint();
    pt.x = e.clientX;
    pt.y = e.clientY;
    return pt.matrixTransform(svg.getScreenCTM().inverse());
  },
};

export default GraphCanvas;
