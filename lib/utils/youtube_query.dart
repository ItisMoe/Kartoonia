import '../models/content_item.dart';

/// Builds the YouTube search query for the detail-screen trailer/theme button.
/// Movies look for a trailer; shows look for their Arabic theme song.
String youtubeSearchQuery(ContentItem item) =>
    item is Movie ? '${item.title} trailer' : '${item.title} arabic theme song';
