/// Count labels shared by visible text, screen-reader descriptions and PDF.
String countNoun(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';
