import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';

void main() async {
  final g = EntityGraphService.withSqliteCanvasStore(
    memoryStore: MemoryStore(),
    doorStore: ProjectDoorStore(),
    assetStore: DigitalAssetRegistryStore(),
  );
  final nodes = await g.getCanvasNodes(canvasId: null);
  print('total nodes: ${nodes.length}');
  for (final e in nodes) {
    final nt = e.props.nodeType;
    if (nt != null && nt.toString().contains('schedule')) {
      print('SCHEDULE: ${e.entity.id} | ${e.entity.title} | canvas=${e.props.canvasId} | params=${e.props.params}');
    }
  }
  final types = <String, int>{};
  for (final e in nodes) {
    final k = e.props.nodeType?.name ?? 'null';
    types[k] = (types[k] ?? 0) + 1;
  }
  print('types: $types');
}
