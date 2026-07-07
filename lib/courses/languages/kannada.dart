// Project imports:
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/reading_question.dart';
import 'package:words625/domain/course/section.dart';
import 'package:words625/domain/course/stage.dart';
import 'package:words625/domain/course/unit.dart';

/// Top-level Kannada course structure: 3 sections → units → lessons → stages.
///
/// The full curriculum eventually spans 12 thematic units (see the legacy
/// 2-layer [getKannadaData] function kept below for backward compatibility).
/// Here we provide a representative 5-layer tree that exercises every
/// [LessonType] and every [Interaction] variant.
List<Section> getKannadaSections() => _kannadaSections;

final List<Section> _kannadaSections = [
  // ───────────────────────── Section 1 — Foundations ─────────────────────────
  Section(
    id: 's-foundations',
    name: 'Foundations',
    description: 'Greetings, pronouns, and the basics of being polite.',
    units: [
      Unit(
        id: 's-foundations-u-greetings',
        name: 'Greetings',
        description: 'How to say hello and introduce yourself.',
        lessons: [
          Lesson(
            id: 'l-greetings-1',
            name: 'Hello & Yes/No',
            type: LessonType.normal,
            content: LessonContent.normal(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-naanu', context: 'Naanu vidyaarthi. — I am a student.'),
                  const Interaction.showWord(wordId: 'w-neenu'),
                  const Interaction.showWord(wordId: 'w-howdu'),
                  const Interaction.showWord(wordId: 'w-illa'),
                ],
              ),
              Stage(
                id: 'stage-practice',
                name: 'Practice',
                items: [
                  const Interaction.multipleChoice(
                    prompt: 'Which word means "Yes"?',
                    options: ['Howdu', 'Illa', 'Baa', 'Hogu'],
                    correctIndex: 0,
                  ),
                  const Interaction.fillBlank(
                    sentence: '_____ = "No" in Kannada',
                    answer: 'Illa',
                    hint: 'Starts with "I"',
                  ),
                  const Interaction.listenAndPick(
                    audioAsset: 'w-howdu',
                    prompt: 'What did you hear?',
                    options: ['Yes', 'No', 'Come', 'Go'],
                    correctIndex: 0,
                  ),
                ],
              ),
            ]),
          ),
          Lesson(
            id: 'l-greetings-2',
            name: 'Pronouns',
            type: LessonType.listening,
            content: LessonContent.listening(
              audioAsset: 'section:foundations',
              stages: [
                Stage(
                  id: 'stage-vocab',
                  name: 'Vocabulary',
                  items: [
                    const Interaction.showWord(wordId: 'w-naavu'),
                    const Interaction.showWord(wordId: 'w-neenu'),
                  ],
                ),
                Stage(
                  id: 'stage-listen',
                  name: 'Listening drill',
                  items: [
                    const Interaction.typeTheWord(
                      audioAsset: 'w-naavu',
                      prompt: 'Type the word you hear',
                      expected: 'Naavu',
                    ),
                    const Interaction.reorderSentence(
                      scrambled: ['Naavu', 'vidyaarthi'],
                      correct: ['Naavu', 'vidyaarthi'],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      Unit(
        id: 's-foundations-u-intro',
        name: 'Introductions',
        description: 'Saying who you are.',
        lessons: [
          Lesson(
            id: 'l-intro-1',
            name: 'What is your name?',
            type: LessonType.normal,
            content: LessonContent.normal(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-hesaru'),
                  const Interaction.showWord(wordId: 'w-vidyaarthi'),
                ],
              ),
              Stage(
                id: 'stage-translate',
                name: 'Translate',
                items: [
                  const Interaction.translateSentence(
                    source: 'Naanu vidyaarthi.',
                    expected: 'I am a student.',
                  ),
                  const Interaction.multipleChoice(
                    prompt: '"My name is ___" in Kannada',
                    options: [
                      'Nanna hesaru ___',
                      'Naanu ___',
                      'Neenu ___'
                    ],
                    correctIndex: 0,
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    ],
  ),

  // ───────────────────────── Section 2 — Daily Life ─────────────────────────
  Section(
    id: 's-daily',
    name: 'Daily Life',
    description: 'The world immediately around you — colors, animals, numbers.',
    units: [
      Unit(
        id: 's-daily-u-animals',
        name: 'Animals',
        description: 'Pets and wildlife of Karnataka.',
        lessons: [
          Lesson(
            id: 'l-animals-1',
            name: 'Common animals',
            type: LessonType.normal,
            content: LessonContent.normal(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-naayi'),
                  const Interaction.showWord(wordId: 'w-koli'),
                  const Interaction.showWord(wordId: 'w-aane'),
                  const Interaction.showWord(wordId: 'w-bekku'),
                ],
              ),
              Stage(
                id: 'stage-practice',
                name: 'Practice',
                items: [
                  const Interaction.multipleChoice(
                    prompt: 'Which is "Elephant"?',
                    options: ['Naayi', 'Koli', 'Aane', 'Bekku'],
                    correctIndex: 2,
                  ),
                  const Interaction.fillBlank(
                    sentence: '_____ = Cat (colloquial)',
                    answer: 'Bekku',
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
      Unit(
        id: 's-daily-u-colors',
        name: 'Colors',
        description: 'Describe what you see.',
        lessons: [
          Lesson(
            id: 'l-colors-1',
            name: 'Primary colors',
            type: LessonType.normal,
            content: LessonContent.normal(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-kempu'),
                  const Interaction.showWord(wordId: 'w-bili'),
                  const Interaction.showWord(wordId: 'w-kappu'),
                  const Interaction.showWord(wordId: 'w-hasiru'),
                ],
              ),
              Stage(
                id: 'stage-listen',
                name: 'Listening',
                items: [
                  const Interaction.listenAndPick(
                    audioAsset: 'w-kempu',
                    prompt: 'Pick the color you hear',
                    options: ['Red', 'White', 'Black', 'Green'],
                    correctIndex: 0,
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
      Unit(
        id: 's-daily-u-numbers',
        name: 'Numbers',
        description: 'Count from 1 to 5.',
        lessons: [
          Lesson(
            id: 'l-numbers-1',
            name: 'One to five',
            type: LessonType.challenge,
            content: LessonContent.challenge(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-ondu'),
                  const Interaction.showWord(wordId: 'w-eradu'),
                  const Interaction.showWord(wordId: 'w-mooru'),
                  const Interaction.showWord(wordId: 'w-naaku'),
                  const Interaction.showWord(wordId: 'w-aidhu'),
                ],
              ),
              Stage(
                id: 'stage-quiz',
                name: 'Quick quiz',
                items: [
                  const Interaction.multipleChoice(
                    prompt: '"Five" in Kannada',
                    options: ['Naaku', 'Aidhu', 'Mooru', 'Eradu'],
                    correctIndex: 1,
                  ),
                  const Interaction.reorderSentence(
                    scrambled: ['Mooru', 'ondu', 'aidhu'],
                    correct: ['Ondu', 'eradu', 'mooru'],
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    ],
  ),

  // ───────────────────────── Section 3 — World Around ─────────────────────────
  Section(
    id: 's-world',
    name: 'World Around',
    description: 'Emotions, nature, and getting around.',
    units: [
      Unit(
        id: 's-world-u-emotions',
        name: 'Emotions',
        description: 'How are you feeling?',
        lessons: [
          Lesson(
            id: 'l-emotions-1',
            name: 'Basic feelings',
            type: LessonType.reading,
            content: LessonContent.reading(
              text: 'Naanu santosha. Neenu santosha. Naavu santosha. '
                  'Avaru dukha. Yaavaru santosha? Yaavaru dukha?',
              stages: [
                ReadingStage(
                  id: 'stage-vocab',
                  name: 'Vocabulary',
                  items: [
                    const ReadingQuestion.mcq(
                      prompt: 'What does "Naanu santosha" mean?',
                      options: ['I am happy', 'I am sad', 'I am angry'],
                      correctIndex: 0,
                    ),
                  ],
                ),
                ReadingStage(
                  id: 'stage-comprehension',
                  name: 'Comprehension',
                  items: [
                    const ReadingQuestion.trueFalse(
                      statement: 'Naavu santosha means "We are happy".',
                      answer: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      Unit(
        id: 's-world-u-nature',
        name: 'Nature',
        description: 'Trees, flowers, water.',
        lessons: [
          Lesson(
            id: 'l-nature-1',
            name: 'Outdoors',
            type: LessonType.normal,
            content: LessonContent.normal(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-mara'),
                  const Interaction.showWord(wordId: 'w-huvu'),
                  const Interaction.showWord(wordId: 'w-neeru'),
                  const Interaction.showWord(wordId: 'w-bhoomi'),
                ],
              ),
              Stage(
                id: 'stage-practice',
                name: 'Practice',
                items: [
                  const Interaction.fillBlank(
                    sentence: 'Mara = ____',
                    answer: 'Tree',
                  ),
                  const Interaction.listenAndPick(
                    audioAsset: 'w-neeru',
                    prompt: 'What do you hear?',
                    options: ['Water', 'Earth', 'Tree', 'Flower'],
                    correctIndex: 0,
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
      Unit(
        id: 's-world-u-travel',
        name: 'Travel',
        description: 'Getting from A to B.',
        lessons: [
          Lesson(
            id: 'l-travel-1',
            name: 'Transportation',
            type: LessonType.review,
            content: LessonContent.review(stages: [
              Stage(
                id: 'stage-vocab',
                name: 'Vocabulary',
                items: [
                  const Interaction.showWord(wordId: 'w-prayan'),
                  const Interaction.showWord(wordId: 'w-rail'),
                  const Interaction.showWord(wordId: 'w-bus'),
                  const Interaction.showWord(wordId: 'w-hotel'),
                ],
              ),
              Stage(
                id: 'stage-recall',
                name: 'Recall drill',
                items: [
                  const Interaction.translateSentence(
                    source: 'Naanu bus alli hoduthene.',
                    expected: 'I am going in a bus.',
                    hints: ['bus', 'go'],
                  ),
                  const Interaction.multipleChoice(
                    prompt: 'Where do you sleep on a trip?',
                    options: ['Hotel', 'Train', 'Bus', 'Earth'],
                    correctIndex: 0,
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    ],
  ),
];
