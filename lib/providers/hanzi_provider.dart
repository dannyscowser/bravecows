import 'package:flutter/foundation.dart';

import '../models/character.dart';
import '../models/study_list.dart';
import '../services/db_service.dart';

class HanziProvider extends ChangeNotifier {
  DisplayScript displayScript = DisplayScript.traditional;
  final List<StudyList> _lists = [];
  final Map<String, bool> _knownCache = {};
  final Set<String> _studySet = {};
  int? _defaultListId;
  List<Character> _dueQueue = [];
  List<Character> _practiceQueue = [];
  List<Character> _knownCharacters = [];
  bool _loadingDue = false;

  List<Character> get dueQueue => List.unmodifiable(_dueQueue);
  List<Character> get practiceQueue => List.unmodifiable(_practiceQueue);
  bool get loadingDue => _loadingDue;
  int get dueCount => _dueQueue.length;
  Set<String> get studySet => Set.unmodifiable(_studySet);
  List<StudyList> get lists => List.unmodifiable(_lists);
  int? get defaultListId => _defaultListId;
  List<Character> get knownCharacters => List.unmodifiable(_knownCharacters);

  void _removeFromQueues(String traditional) {
    _dueQueue.removeWhere((c) => c.traditional == traditional);
    _practiceQueue.removeWhere((c) => c.traditional == traditional);
  }

  Future<void> load() async {
    _defaultListId = await DBService.instance.defaultListId();
    final fetchedLists = await DBService.instance.getLists();
    _lists
      ..clear()
      ..addAll(fetchedLists);
    for (final l in _lists) {
      if (l.isSystem) {
        await DBService.instance.populateSystemList(l);
      }
    }
    if (_defaultListId != null) {
      await DBService.instance.ensureAssetListPopulated(_defaultListId!);
    }
    _studySet
      ..clear()
      ..addAll(await DBService.instance.getStudySet(listId: _defaultListId));
    await loadDueQueue();
  }

  Future<void> _ensureActiveSystemListPopulated() async {
    final listId = _defaultListId ?? await DBService.instance.defaultListId();
    StudyList? active =
        _lists.cast<StudyList?>().firstWhere((l) => l?.id == listId, orElse: () => null);
    // Refresh lists if not found or missing system metadata.
    if (active == null || active.rangeStart == null || active.rangeEnd == null) {
      final refreshed = await DBService.instance.getLists();
      _lists
        ..clear()
        ..addAll(refreshed);
      active = _lists.cast<StudyList?>().firstWhere((l) => l?.id == listId, orElse: () => null);
    }
    if (active != null && active.isSystem) {
      await DBService.instance.populateSystemList(active);
    }
    if (active != null) {
      await DBService.instance.ensureAssetListPopulated(active.id);
    }
  }

  Future<void> loadDueQueue({int limitUnknown = 25, int limitKnown = 0}) async {
    await _ensureActiveSystemListPopulated();
    _loadingDue = true;
    notifyListeners();
    // Always pull a fresh batch of unknowns from the active list so "Practice now"
    // is never empty, even if nothing is technically due yet.
    _dueQueue = await DBService.instance.getPracticeCharacters(
      listId: _defaultListId,
      limitUnknown: limitUnknown,
      limitKnown: 0,
      seed: DateTime.now().microsecondsSinceEpoch,
    );
    _dueQueue.shuffle();
    _loadingDue = false;
    notifyListeners();
  }

  Future<void> loadPracticeQueue() async {
    await _ensureActiveSystemListPopulated();
    _practiceQueue = await DBService.instance.getPracticeCharacters(
        listId: _defaultListId,
        limitUnknown: 25,
        limitKnown: 0,
        seed: DateTime.now().microsecondsSinceEpoch);
    _practiceQueue.shuffle();
    notifyListeners();
  }

  Future<void> loadPracticeQueueAll({int? limit, int offset = 0}) async {
    await _ensureActiveSystemListPopulated();
    final listId = _defaultListId ?? await DBService.instance.defaultListId();
    _practiceQueue = await DBService.instance
        .getAllCharactersForList(listId,
            limit: limit, offset: offset, includeKnown: false);
    _practiceQueue.shuffle();
    notifyListeners();
  }

  Future<void> loadWrongsAllTime({int? limit}) async {
    _practiceQueue = await DBService.instance.getWrongCharactersForList(
      _defaultListId,
      limit: limit,
    );
    notifyListeners();
  }

  void setPracticeQueue(List<Character> items) {
    _practiceQueue = List<Character>.from(items);
    notifyListeners();
  }

  void setDisplayScript(DisplayScript script) {
    displayScript = script;
    notifyListeners();
  }

  String displayHanzi(Character c) {
    return displayScript == DisplayScript.traditional
        ? c.traditional
        : c.simplified;
  }

  Future<List<Character>> loadLearnBatch(
      {int total = 25, int maxKnown = 5, int? seed}) async {
    return DBService.instance.getLearnBatch(
        total: total,
        maxKnown: maxKnown,
        seed: seed,
        excludeListId: _defaultListId);
  }

  Future<List<Character>> loadLearnBand(
      {int start = 0, int size = 100}) {
    return DBService.instance.getLearnBand(
        start: start, size: size, excludeListId: _defaultListId);
  }

  Future<bool> isKnown(String traditional) async {
    if (_knownCache.containsKey(traditional)) {
      return _knownCache[traditional]!;
    }
    final known = await DBService.instance.isKnown(traditional);
    _knownCache[traditional] = known;
    return known;
  }

  Future<void> recordReview(String traditional, bool correct,
      {int? listId}) async {
    await DBService.instance
        .insertReview(traditional, correct, listId: listId ?? _defaultListId);
    _knownCache.remove(traditional);
    _removeFromQueues(traditional);
    notifyListeners();
  }

  Future<void> markKnown(String traditional) async {
    await DBService.instance.markKnown(traditional, listId: _defaultListId);
    await DBService.instance
        .insertReview(traditional, true, listId: _defaultListId);
    _knownCache[traditional] = true;
    _removeFromQueues(traditional);
    notifyListeners();
  }

  Future<void> undoLastReview(Character card) async {
    await DBService.instance.undoLastReview(card.traditional);
    _knownCache.remove(card.traditional);
    _removeFromQueues(card.traditional);
    _dueQueue.insert(0, card);
    _practiceQueue.insert(0, card);
    notifyListeners();
  }

  Future<void> addToStudy(String traditional) async {
    await DBService.instance.addToStudy(traditional, listId: _defaultListId);
    _studySet.add(traditional);
    await loadDueQueue();
    notifyListeners();
  }

  Future<void> removeFromStudy(String traditional) async {
    await DBService.instance
        .removeFromStudy(traditional, listId: _defaultListId);
    _studySet.remove(traditional);
    _knownCache.remove(traditional);
    await loadDueQueue();
    notifyListeners();
  }

  Future<void> addToList(String traditional, int listId,
      {String? meaning}) async {
    await DBService.instance.addToList(traditional, listId, meaning: meaning);
    if (listId == _defaultListId) {
      _studySet.add(traditional);
      await loadDueQueue();
    }
    notifyListeners();
  }

  Future<int> createList(String name, {String? emoji}) async {
    final id = await DBService.instance.createList(name, emoji: emoji);
    _lists.add(StudyList(id: id, name: name, emoji: emoji));
    notifyListeners();
    return id;
  }

  Future<void> setActiveList(int listId) async {
    _defaultListId = listId;
    await DBService.instance.setDefaultListId(listId);
    final active = _lists.firstWhere((l) => l.id == listId,
        orElse: () => StudyList(id: listId, name: 'List', emoji: null));
    if (active.isSystem) {
      await DBService.instance.populateSystemList(active);
    }
    await DBService.instance.ensureAssetListPopulated(listId);
    _studySet
      ..clear()
      ..addAll(await DBService.instance.getStudySet(listId: _defaultListId));
    await loadDueQueue();
    notifyListeners();
  }

  Future<void> loadKnownCharacters() async {
    _knownCharacters = await DBService.instance.getKnownCharacters();
    notifyListeners();
  }

  void skipCard(Character card, PracticeMode mode) {
    final queue = switch (mode) {
      PracticeMode.due => _dueQueue,
      PracticeMode.all => _practiceQueue,
      PracticeMode.wrongs => _practiceQueue,
    };
    queue.removeWhere((c) => c.traditional == card.traditional);
    queue.add(card);
    notifyListeners();
  }
}

enum DisplayScript { traditional, simplified }

enum PracticeMode { due, all, wrongs }
