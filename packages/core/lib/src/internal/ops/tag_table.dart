part of '../core_ops.dart';

const kTagTable = 'table';
const kTagTableRow = 'tr';
const kTagTableHeaderGroup = 'thead';
const kTagTableRowGroup = 'tbody';
const kTagTableFooterGroup = 'tfoot';
const kTagTableHeaderCell = 'th';
const kTagTableCell = 'td';
const kTagTableCaption = 'caption';

const kAttributeBorder = 'border';
const kAttributeCellPadding = 'cellpadding';
const kAttributeColspan = 'colspan';
const kAttributeCellSpacing = 'cellspacing';
const kAttributeRowspan = 'rowspan';
const kAttributeValign = 'valign';

const kCssBorderCollapse = 'border-collapse';
const kCssBorderCollapseCollapse = 'collapse';
const kCssBorderCollapseSeparate = 'separate';
const kCssBorderSpacing = 'border-spacing';

const kCssDisplayTable = 'table';
const kCssDisplayTableRow = 'table-row';
const kCssDisplayTableHeaderGroup = 'table-header-group';
const kCssDisplayTableRowGroup = 'table-row-group';
const kCssDisplayTableFooterGroup = 'table-footer-group';
const kCssDisplayTableCell = 'table-cell';
const kCssDisplayTableCaption = 'table-caption';

class TagTable {
  final companion = HtmlTableCompanion();
  final BuildMetadata tableMeta;
  final WidgetFactory wf;

  final _captions = <BuildTree>[];
  final _data = _TagTableData();

  BuildOp _tableOp;

  TagTable(this.wf, this.tableMeta);

  BuildOp get op {
    _tableOp = BuildOp(
      onChild: onChild,
      onTree: onTree,
      onWidgets: onWidgets,
      priority: 0,
    );
    return _tableOp;
  }

  void onChild(BuildMetadata childMeta) {
    if (childMeta.element.parent != tableMeta.element) return;

    final which = _getCssDisplayValue(childMeta);
    _TagTableDataGroup latestGroup;
    switch (which) {
      case kCssDisplayTableRow:
        latestGroup ??= _data.body;
        final row = _TagTableDataRow();
        latestGroup.rows.add(row);
        childMeta.register(_TagTableRow(this, childMeta, row).op);
        break;
      case kCssDisplayTableHeaderGroup:
      case kCssDisplayTableRowGroup:
      case kCssDisplayTableFooterGroup:
        final rows = which == kCssDisplayTableHeaderGroup
            ? _data.header.rows
            : which == kCssDisplayTableRowGroup
                ? _data.body.rows
                : _data.footer.rows;
        childMeta.register(_TagTableRowGroup(this, childMeta, rows).op);
        latestGroup = null;
        break;
      case kCssDisplayTableCaption:
        childMeta.register(BuildOp(onTree: (_, tree) => _captions.add(tree)));
        break;
    }
  }

  void onTree(BuildMetadata _, BuildTree tree) {
    for (final caption in _captions) {
      final built = wf
          .buildColumnPlaceholder(tableMeta, caption.build())
          ?.wrapWith((_, child) => _TableCaption(child));
      if (built != null) {
        WidgetBit.block(tree.parent, built).insertBefore(tree);
      }

      caption.detach();
    }
  }

  Iterable<Widget> onWidgets(BuildMetadata _, Iterable<WidgetPlaceholder> __) {
    final children = <HtmlTableCell>[];
    // occupations data: { rowId: { columnId: occupied } }
    final occupations = <int, Map<int, bool>>{};
    _buildHtmlTableCells(_data.header, occupations, children);
    for (final body in _data.bodies) {
      _buildHtmlTableCells(body, occupations, children);
    }
    _buildHtmlTableCells(_data.footer, occupations, children);
    if (children.isEmpty) return [];

    CssLength borderSpacing;
    var collapseBorder = false;
    for (final style in tableMeta.styles) {
      switch (style.key) {
        case kCssBorderCollapse:
          switch (style.value) {
            case kCssBorderCollapseCollapse:
              collapseBorder = true;
              break;
            case kCssBorderCollapseSeparate:
              collapseBorder = false;
              break;
          }
          break;
        case kCssBorderSpacing:
          final cssLength = tryParseCssLength(style.value);
          if (cssLength != null) borderSpacing = cssLength;
          break;
      }
    }

    final tableBorder = tryParseBorder(tableMeta);

    return [
      WidgetPlaceholder<BuildMetadata>(tableMeta).wrapWith((context, _) {
        final tsh = tableMeta.tsb().build(context);
        final border = tableBorder?.getValue(tsh);
        final spacing = borderSpacing?.getValue(tsh) ?? 0.0;

        return HtmlTable(
          companion: companion,
          children: children,
          columnGap: border != null && collapseBorder
              ? (border.left.width * -1.0)
              : spacing,
          rowGap: border != null && collapseBorder
              ? (border.top.width * -1.0)
              : spacing,
        );
      }),
    ];
  }

  static BuildOp cellPaddingOp(double px) => BuildOp(
      onChild: (meta) =>
          (meta.element.localName == 'td' || meta.element.localName == 'th')
              ? meta[kCssPadding] = '${px}px'
              : null);

  static BuildOp borderOp(double border, double borderSpacing) => BuildOp(
      defaultStyles: (_) => {
            kCssBorder: '${border}px solid black',
            kCssBorderCollapse: kCssBorderCollapseSeparate,
            kCssBorderSpacing: '${borderSpacing}px',
          },
      onChild: (meta) =>
          (meta.element.localName == 'td' || meta.element.localName == 'th')
              ? meta[kCssBorder] = '${border}px solid black'
              : null);

  static void _buildHtmlTableCells(_TagTableDataGroup group,
      Map<int, Map<int, bool>> occupations, List<HtmlTableCell> cells) {
    var rowStart = occupations.keys.length - 1;
    final rowSpanMax = group.rows.length;
    for (final row in group.rows) {
      rowStart++;
      occupations[rowStart] ??= {};

      for (final cell in row.cells) {
        var columnStart = 0;
        while (occupations[rowStart].containsKey(columnStart)) {
          columnStart++;
        }

        final columnSpan = cell.colspan > 0 ? cell.colspan : 1;
        final rowSpan = min(
            rowSpanMax,
            cell.rowspan > 0
                ? cell.rowspan
                : cell.rowspan == 0
                    ? group.rows.length
                    : 1);
        for (var r = 0; r < rowSpan; r++) {
          final row = rowStart + r;
          occupations[row] ??= {};
          for (var c = 0; c < columnSpan; c++) {
            occupations[row][columnStart + c] = true;
          }
        }

        cell.meta.row = rowStart;
        cells.add(HtmlTableCell(
          child: cell.child,
          columnSpan: columnSpan,
          columnStart: columnStart,
          rowSpan: rowSpan,
          rowStart: rowStart,
        ));
      }
    }
  }

  static String _getCssDisplayValue(BuildMetadata meta) {
    String value;
    switch (meta.element.localName) {
      case kTagTableRow:
        value = kCssDisplayTableRow;
        break;
      case kTagTableHeaderGroup:
        value = kCssDisplayTableHeaderGroup;
        break;
      case kTagTableRowGroup:
        value = kCssDisplayTableRowGroup;
        break;
      case kTagTableFooterGroup:
        value = kCssDisplayTableFooterGroup;
        break;
      case kTagTableHeaderCell:
      case kTagTableCell:
        return kCssDisplayTableCell;
      case kTagTableCaption:
        return kCssDisplayTableCaption;
    }

    if (value != null) {
      meta[kCssDisplay] = value;
      return value;
    }

    for (final pair in meta.element.styles.reversed) {
      if (pair.key == kCssDisplay) {
        return pair.value;
      }
    }

    return null;
  }
}

extension _BuildMetadataExtension on BuildMetadata {
  static final _rows = Expando<int>();

  set row(int v) => _rows[this] = v;
  int get row => _rows[this];
}

class _TableCaption extends SingleChildRenderObjectWidget {
  _TableCaption(Widget child, {Key key}) : super(child: child, key: key);

  @override
  RenderObject createRenderObject(BuildContext context) => RenderProxyBox();
}

class _TagTableRow {
  final TagTable parent;
  final _TagTableDataRow row;
  final BuildMetadata rowMeta;

  BuildOp op;
  BuildOp _cellOp;
  BuildOp _valignBaselineOp;

  _TagTableRow(this.parent, this.rowMeta, this.row) {
    op = BuildOp(onChild: onChild);
  }

  void onChild(BuildMetadata childMeta) {
    if (childMeta.element.parent != rowMeta.element) return;
    if (TagTable._getCssDisplayValue(childMeta) != kCssDisplayTableCell) {
      return;
    }

    final attrs = childMeta.element.attributes;
    if (attrs.containsKey(kAttributeValign)) {
      childMeta[kCssVerticalAlign] = attrs[kAttributeValign];
    }

    _cellOp ??= BuildOp(
      onWidgets: (cellMeta, widgets) {
        final column = parent.wf.buildColumnPlaceholder(cellMeta, widgets);
        if (column == null) return [];

        final attributes = cellMeta.element.attributes;
        row.cells.add(_TagTableDataCell(
          cellMeta,
          child: column,
          colspan: tryParseIntFromMap(attributes, kAttributeColspan) ?? 1,
          rowspan: tryParseIntFromMap(attributes, kAttributeRowspan) ?? 1,
        ));

        return [column];
      },
      priority: BuildOp.kPriorityMax,
    );
    childMeta.register(_cellOp);

    _valignBaselineOp ??= BuildOp(
      onWidgets: (cellMeta, widgets) {
        final v = cellMeta[kCssVerticalAlign];
        if (v != kCssVerticalAlignBaseline) return widgets;

        return listOrNull(parent.wf
            .buildColumnPlaceholder(cellMeta, widgets)
            ?.wrapWith((_, child) {
          final row = cellMeta.row;
          if (row == null) return child;

          return HtmlTableValignBaseline(
            child: child,
            companion: parent.companion,
            row: row,
          );
        }));
      },
      priority: StyleVerticalAlign.kPriority4500,
    );
    childMeta.register(_valignBaselineOp);
  }
}

class _TagTableRowGroup {
  final TagTable parent;
  final List<_TagTableDataRow> rows;
  final BuildMetadata groupMeta;

  BuildOp op;

  _TagTableRowGroup(this.parent, this.groupMeta, this.rows) {
    op = BuildOp(onChild: onChild);
  }

  void onChild(BuildMetadata childMeta) {
    if (childMeta.element.parent != groupMeta.element) return;
    if (TagTable._getCssDisplayValue(childMeta) != kCssDisplayTableRow) {
      return;
    }

    final row = _TagTableDataRow();
    rows.add(row);
    childMeta.register(_TagTableRow(parent, childMeta, row).op);
  }
}

@immutable
class _TagTableData {
  final bodies = <_TagTableDataGroup>[];
  final footer = _TagTableDataGroup();
  final header = _TagTableDataGroup();

  _TagTableDataGroup get body {
    final body = _TagTableDataGroup();
    bodies.add(body);
    return body;
  }
}

@immutable
class _TagTableDataGroup {
  final rows = <_TagTableDataRow>[];
}

@immutable
class _TagTableDataRow {
  final cells = <_TagTableDataCell>[];
}

@immutable
class _TagTableDataCell {
  final Widget child;
  final int colspan;
  final BuildMetadata meta;
  final int rowspan;

  _TagTableDataCell(this.meta, {this.child, this.colspan, this.rowspan});
}
