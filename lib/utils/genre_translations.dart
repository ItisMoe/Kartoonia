/// Arabic display names for TMDB genres. Falls back to the raw name if unmapped.
const Map<String, String> _genreAr = {
  'Animation': 'رسوم متحركة',
  'Action': 'أكشن',
  'Adventure': 'مغامرات',
  'Comedy': 'كوميديا',
  'Drama': 'دراما',
  'Fantasy': 'خيال',
  'Family': 'عائلي',
  'Kids': 'أطفال',
  'Mystery': 'غموض',
  'Romance': 'رومانسية',
  'Science Fiction': 'خيال علمي',
  'Thriller': 'إثارة',
  'Horror': 'رعب',
  'Crime': 'جريمة',
  'Documentary': 'وثائقي',
  'Music': 'موسيقى',
  'War': 'حرب',
  'Western': 'غرب',
  'History': 'تاريخ',
  'Sport': 'رياضة',
};

String translateGenre(String genre) => _genreAr[genre] ?? genre;
