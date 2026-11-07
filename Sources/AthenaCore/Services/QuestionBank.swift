import Foundation

/// Curated fallback exercises used when Ollama is unavailable or returns something invalid.
/// Every `predict_output` snippet is a `main` body (with `java.util.*` imported) and is checked
/// against a real JDK by `athena verify-bank`.
public enum QuestionBank {
    public static let all: [JavaChallenge] = predictOutput + apiRecall + openEnded

    public static func challenges(topic: String) -> [JavaChallenge] {
        all.filter { $0.topic.caseInsensitiveCompare(topic) == .orderedSame }
    }

    /// Deterministic pick: prefer unused questions matching topic, type and difficulty, relaxing constraints in order.
    public static func pick(for request: ExerciseRequest, excluding used: Set<String>) -> JavaChallenge? {
        let topical = challenges(topic: request.topic)
        let fresh = topical.filter { !used.contains($0.id) }
        let candidates: [[JavaChallenge]] = [
            fresh.filter { $0.type == request.type && $0.difficulty == request.difficulty },
            fresh.filter { $0.type == request.type },
            fresh.filter { $0.difficulty == request.difficulty },
            fresh,
            topical,
            all.filter { !used.contains($0.id) },
            all,
        ]
        return candidates.first(where: { !$0.isEmpty })?.first
    }

    // MARK: - Predict the output (graded deterministically)

    static let predictOutput: [JavaChallenge] = [
        JavaChallenge(
            id: "bank-pq-1", topic: "PriorityQueue", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                PriorityQueue<Integer> pq = new PriorityQueue<>(List.of(5, 1, 4, 2));
                pq.poll();
                System.out.println(pq.peek());
                """,
            expectedAnswer: "2",
            explanation: "A PriorityQueue with natural ordering is a min-heap. poll() removes 1, so the new head is 2."),
        JavaChallenge(
            id: "bank-pq-2", topic: "PriorityQueue", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                PriorityQueue<String> pq = new PriorityQueue<>((a, b) -> b.length() - a.length());
                pq.addAll(List.of("kiwi", "fig", "banana", "apple"));
                StringBuilder sb = new StringBuilder();
                while (!pq.isEmpty()) sb.append(pq.poll().charAt(0));
                System.out.println(sb);
                """,
            expectedAnswer: "bakf",
            explanation: "The comparator orders by length descending (a max-heap on length): banana(6), apple(5), kiwi(4), fig(3). Only poll() order is guaranteed — iterating a PriorityQueue is not sorted."),
        JavaChallenge(
            id: "bank-map-1", topic: "HashMap", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                Map<String, Integer> m = new HashMap<>();
                m.put("a", 1);
                m.put("a", m.getOrDefault("a", 0) + 5);
                m.putIfAbsent("a", 100);
                System.out.println(m.get("a") + " " + m.size());
                """,
            expectedAnswer: "6 1",
            explanation: "put replaces the value for an existing key (1 → 6). putIfAbsent does nothing because \"a\" is present. There is still one key."),
        JavaChallenge(
            id: "bank-map-2", topic: "HashMap", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                Map<Character, Integer> freq = new HashMap<>();
                for (char c : "banana".toCharArray()) freq.merge(c, 1, Integer::sum);
                System.out.println(freq.get('a') + freq.get('n'));
                """,
            expectedAnswer: "5",
            explanation: "merge(c, 1, Integer::sum) counts characters: a=3, n=2. Integer + Integer unboxes to int addition, so it prints 5, not \"32\"."),
        JavaChallenge(
            id: "bank-set-1", topic: "HashSet", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                Set<Integer> s = new HashSet<>(List.of(3, 1, 3, 2, 1));
                System.out.println(s.size() + " " + s.add(2) + " " + s.add(4));
                """,
            expectedAnswer: "3 false true",
            explanation: "Duplicates collapse to {1, 2, 3}. add returns false when the element is already present and true when it was added."),
        JavaChallenge(
            id: "bank-list-1", topic: "ArrayList", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                List<Integer> list = new ArrayList<>(List.of(10, 20, 30, 40));
                list.remove(1);
                list.remove(Integer.valueOf(40));
                System.out.println(list);
                """,
            expectedAnswer: "[10, 30]",
            explanation: "remove(int) removes by index (20 at index 1). remove(Object) removes by value, so Integer.valueOf(40) removes 40."),
        JavaChallenge(
            id: "bank-ll-1", topic: "LinkedList", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                LinkedList<Integer> ll = new LinkedList<>();
                ll.add(1); ll.addFirst(2); ll.addLast(3); ll.push(4);
                System.out.println(ll.pop() + " " + ll.peekLast() + " " + ll);
                """,
            expectedAnswer: "4 3 [2, 1, 3]",
            explanation: "push adds to the front, so the list is [4, 2, 1, 3]. pop removes the front (4); peekLast reads 3 without removing."),
        JavaChallenge(
            id: "bank-deque-1", topic: "ArrayDeque", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                Deque<Integer> dq = new ArrayDeque<>();
                dq.offer(1); dq.offer(2); dq.push(3);
                System.out.println(dq.pollLast() + " " + dq.peekFirst());
                """,
            expectedAnswer: "2 3",
            explanation: "offer adds at the tail, push adds at the head: [3, 1, 2]. pollLast removes 2; peekFirst reads 3."),
        JavaChallenge(
            id: "bank-str-1", topic: "String", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                String a = "hello";
                String b = new String("hello");
                String c = b.intern();
                System.out.println((a == b) + " " + (a == c) + " " + a.equals(b));
                """,
            expectedAnswer: "false true true",
            explanation: "new String creates a distinct object, so == is false. intern() returns the pooled literal, the same object as a. equals compares content."),
        JavaChallenge(
            id: "bank-str-2", topic: "String", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                String s = "  Java Interview  ";
                System.out.println(s.trim().substring(5).toUpperCase().indexOf('V'));
                """,
            expectedAnswer: "5",
            explanation: "trim → \"Java Interview\", substring(5) → \"Interview\", upper-cased → \"INTERVIEW\". 'V' is at index 5."),
        JavaChallenge(
            id: "bank-sb-1", topic: "StringBuilder", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                StringBuilder sb = new StringBuilder("abc");
                sb.append("def").reverse().insert(0, 'X').deleteCharAt(sb.length() - 1);
                System.out.println(sb);
                """,
            expectedAnswer: "Xfedcb",
            explanation: "StringBuilder methods mutate and return the same builder. The receiver chain runs first (\"Xfedcba\", length 7), then sb.length() - 1 = 6 is evaluated, deleting the final 'a'."),
        JavaChallenge(
            id: "bank-sort-1", topic: "Sorting", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                int[] arr = {5, 9, 3, 1};
                Arrays.sort(arr, 1, 3);
                System.out.println(Arrays.toString(arr));
                """,
            expectedAnswer: "[5, 3, 9, 1]",
            explanation: "Arrays.sort(arr, from, to) sorts the half-open range [1, 3): only indices 1 and 2 (9, 3) are sorted."),
        JavaChallenge(
            id: "bank-cmp-1", topic: "Comparators", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                List<String> words = new ArrayList<>(List.of("pear", "fig", "apple", "kiwi"));
                words.sort(Comparator.comparing(String::length).thenComparing(Comparator.reverseOrder()));
                System.out.println(words);
                """,
            expectedAnswer: "[fig, pear, kiwi, apple]",
            explanation: "Primary key is length (3, 4, 4, 5). The tie between pear and kiwi is broken in reverse alphabetical order, so pear comes first."),
        JavaChallenge(
            id: "bank-exc-1", topic: "Java exceptions", difficulty: .easy, type: .predictOutput,
            question: "What does this print? (Write each line separated by a space.)",
            code: """
                try {
                    Object o = "42";
                    Integer i = (Integer) o;
                    System.out.println("A");
                } catch (ClassCastException e) {
                    System.out.println("B");
                } finally {
                    System.out.println("C");
                }
                """,
            expectedAnswer: "B\nC",
            explanation: "Casting a String to Integer throws ClassCastException, so \"A\" is skipped, the catch prints B, and finally always runs."),
        JavaChallenge(
            id: "bank-exc-2", topic: "Java exceptions", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                int[] a = new int[2];
                try {
                    a[2] = 1;
                    System.out.print("x");
                } catch (RuntimeException e) {
                    System.out.print(e.getClass().getSimpleName());
                }
                """,
            expectedAnswer: "ArrayIndexOutOfBoundsException",
            explanation: "Index 2 is out of bounds for length 2. ArrayIndexOutOfBoundsException is a RuntimeException, so the catch matches and prints the simple class name."),
        JavaChallenge(
            id: "bank-eq-1", topic: "equals and hashCode", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                class P { int x; P(int x) { this.x = x; } }
                record Point(int x, int y) {}
                Set<P> ps = new HashSet<>(); ps.add(new P(1)); ps.add(new P(1));
                Set<Point> pts = new HashSet<>(); pts.add(new Point(1, 2)); pts.add(new Point(1, 2));
                System.out.println(ps.size() + " " + pts.size());
                """,
            expectedAnswer: "2 1",
            explanation: "P inherits identity equals/hashCode from Object, so two instances are distinct. Records generate value-based equals and hashCode, so the second Point is a duplicate."),
        JavaChallenge(
            id: "bank-gen-1", topic: "Generics", difficulty: .medium, type: .predictOutput,
            question: "What does this print?",
            code: """
                List<Integer> ints = List.of(1, 2, 3);
                List<? extends Number> nums = ints;
                Number first = nums.get(0);
                System.out.println(first.doubleValue() + nums.size());
                """,
            expectedAnswer: "4.0",
            explanation: "List<? extends Number> can be read as Number. 1.0 (double) + 3 (int) is numeric addition promoted to double: 4.0."),
        JavaChallenge(
            id: "bank-api-1", topic: "Java collection APIs", difficulty: .easy, type: .predictOutput,
            question: "What does this print?",
            code: """
                List<Integer> list = Arrays.asList(3, 1, 2);
                Collections.sort(list);
                Collections.reverse(list);
                System.out.println(list + " " + Collections.max(list) + " " + Collections.frequency(list, 2));
                """,
            expectedAnswer: "[3, 2, 1] 3 1",
            explanation: "Arrays.asList is fixed-size but its elements can be reordered, so sort and reverse work. max is 3 and 2 appears once."),
    ]

    // MARK: - API recall (graded deterministically)

    static let apiRecall: [JavaChallenge] = [
        JavaChallenge(
            id: "bank-map-r1", topic: "HashMap", difficulty: .easy, type: .apiRecall,
            question: "Which Map method returns the value for a key, or a fallback value you supply when the key is absent?",
            expectedAnswer: "getOrDefault",
            explanation: "map.getOrDefault(key, defaultValue) avoids a null check; it does not insert the default."),
        JavaChallenge(
            id: "bank-map-r2", topic: "HashMap", difficulty: .medium, type: .apiRecall,
            question: "You are grouping words into Map<String, List<String>>. Which Map method creates the list only when the key is missing and returns it, so you can write map.???(key, k -> new ArrayList<>()).add(word)?",
            expectedAnswer: "computeIfAbsent",
            explanation: "computeIfAbsent runs the mapping function only for absent keys, stores the result, and returns the (new or existing) value."),
        JavaChallenge(
            id: "bank-pq-r1", topic: "PriorityQueue", difficulty: .easy, type: .apiRecall,
            question: "Write the expression that creates a max-heap PriorityQueue<Integer>.",
            expectedAnswer: "new PriorityQueue<>(Collections.reverseOrder())",
            acceptableAnswers: [
                "new PriorityQueue<Integer>(Collections.reverseOrder())",
                "new PriorityQueue<>(Comparator.reverseOrder())",
                "new PriorityQueue<Integer>(Comparator.reverseOrder())",
                "new PriorityQueue<>((a, b) -> b - a)",
                "new PriorityQueue<>((a, b) -> b.compareTo(a))",
                "new PriorityQueue<>((a, b) -> Integer.compare(b, a))",
            ],
            explanation: "PriorityQueue is a min-heap by default; pass a reversed comparator. Prefer Collections.reverseOrder() or Integer.compare over b - a, which can overflow."),
        JavaChallenge(
            id: "bank-deque-r1", topic: "ArrayDeque", difficulty: .easy, type: .apiRecall,
            question: "Which Deque method removes and returns the head, returning null instead of throwing when the deque is empty?",
            expectedAnswer: "poll", acceptableAnswers: ["pollFirst"],
            explanation: "poll()/pollFirst() return null on empty; remove()/pop() throw NoSuchElementException."),
        JavaChallenge(
            id: "bank-ll-r1", topic: "LinkedList", difficulty: .easy, type: .apiRecall,
            question: "Which LinkedList method inserts an element at the front of the list?",
            expectedAnswer: "addFirst", acceptableAnswers: ["offerFirst", "push"],
            explanation: "addFirst, offerFirst and push all insert at the head. add/addLast/offer insert at the tail."),
        JavaChallenge(
            id: "bank-str-r1", topic: "String", difficulty: .easy, type: .apiRecall,
            question: "Which String method (Java 11+) returns true if the string is empty or contains only whitespace?",
            expectedAnswer: "isBlank",
            explanation: "isBlank() checks for whitespace-only content; isEmpty() only checks length == 0."),
        JavaChallenge(
            id: "bank-sb-r1", topic: "StringBuilder", difficulty: .easy, type: .apiRecall,
            question: "Which StringBuilder method sets the character at a given index without creating a new builder?",
            expectedAnswer: "setCharAt",
            explanation: "sb.setCharAt(i, c) mutates in place. Strings are immutable, which is why builders are used for in-place edits."),
        JavaChallenge(
            id: "bank-sort-r1", topic: "Sorting", difficulty: .easy, type: .apiRecall,
            question: "Which call sorts an int[] named arr in place (qualified class + method)?",
            expectedAnswer: "Arrays.sort",
            explanation: "Arrays.sort(arr) sorts primitives with dual-pivot quicksort. Collections.sort only works on Lists."),
        JavaChallenge(
            id: "bank-cmp-r1", topic: "Comparators", difficulty: .easy, type: .apiRecall,
            question: "Which Comparator default method adds a secondary sort key to an existing comparator?",
            expectedAnswer: "thenComparing", acceptableAnswers: ["thenComparingInt", "thenComparingLong", "thenComparingDouble"],
            explanation: "comparator.thenComparing(...) is only consulted when the first comparator returns 0."),
        JavaChallenge(
            id: "bank-api-r1", topic: "Java collection APIs", difficulty: .easy, type: .apiRecall,
            question: "Which Collections method returns a read-only view of a List (changes to the original are still visible)?",
            expectedAnswer: "Collections.unmodifiableList", acceptableAnswers: ["unmodifiableList"],
            explanation: "Collections.unmodifiableList wraps the list. List.copyOf makes an independent immutable copy instead."),
        JavaChallenge(
            id: "bank-set-r1", topic: "HashSet", difficulty: .medium, type: .apiRecall,
            question: "Which Set method keeps only the elements that are also in another collection (set intersection)?",
            expectedAnswer: "retainAll",
            explanation: "a.retainAll(b) mutates a to a ∩ b. addAll is union, removeAll is difference."),
    ]

    // MARK: - Open-ended (graded against criteria)

    static let openEnded: [JavaChallenge] = [
        JavaChallenge(
            id: "bank-eq-c1", topic: "equals and hashCode", difficulty: .medium, type: .explainConcept,
            question: "Why must you override hashCode whenever you override equals? What goes wrong in a HashMap or HashSet if you don't?",
            expectedAnswer: "Equal objects must have equal hash codes. HashMap uses hashCode to choose a bucket and only then calls equals, so two equal keys with different hash codes land in different buckets: get/contains miss the entry and a HashSet can hold logical duplicates.",
            explanation: "The equals/hashCode contract lets hash-based collections narrow the search by hash before comparing with equals.",
            evaluationCriteria: [
                "States the contract: objects that are equal must return the same hashCode",
                "Explains that HashMap/HashSet use hashCode to find the bucket before calling equals",
                "Gives a concrete consequence: lookups fail or duplicates appear",
            ]),
        JavaChallenge(
            id: "bank-list-b1", topic: "ArrayList", difficulty: .medium, type: .identifyBug,
            question: "This should remove all even numbers. What is the bug, and how would you fix it?",
            code: """
                List<Integer> nums = new ArrayList<>(List.of(1, 2, 3, 4));
                for (Integer n : nums) {
                    if (n % 2 == 0) nums.remove(n);
                }
                """,
            expectedAnswer: "Removing from the list inside a for-each loop throws ConcurrentModificationException. Use nums.removeIf(n -> n % 2 == 0) or an explicit Iterator with it.remove().",
            explanation: "The for-each loop uses an Iterator that detects structural modification (modCount) and fails fast.",
            evaluationCriteria: [
                "Identifies ConcurrentModificationException or modifying the list while iterating with for-each",
                "Proposes a correct fix such as removeIf or Iterator.remove()",
            ]),
        JavaChallenge(
            id: "bank-cmp-c1", topic: "Comparators", difficulty: .medium, type: .completeCode,
            question: "Fill in the comparator so people are sorted by age ascending, then by name alphabetically. Person is a record with age() and name().",
            code: "people.sort(________);",
            expectedAnswer: "Comparator.comparingInt(Person::age).thenComparing(Person::name)",
            acceptableAnswers: ["Comparator.comparing(Person::age).thenComparing(Person::name)"],
            explanation: "comparingInt avoids boxing; thenComparing breaks ties by name.",
            evaluationCriteria: [
                "Sorts by age ascending as the primary key",
                "Breaks ties by name in natural (alphabetical) order",
                "Is valid Java that compiles as the argument to people.sort",
            ]),
        JavaChallenge(
            id: "bank-map-s1", topic: "HashMap", difficulty: .medium, type: .smallCoding,
            question: "Write `static char firstUnique(String s)` returning the first character that appears exactly once, or '_' if none. Aim for O(n).",
            expectedAnswer: """
                static char firstUnique(String s) {
                    Map<Character, Integer> count = new HashMap<>();
                    for (char c : s.toCharArray()) count.merge(c, 1, Integer::sum);
                    for (char c : s.toCharArray()) if (count.get(c) == 1) return c;
                    return '_';
                }
                """,
            explanation: "Two passes: count frequencies, then scan in original order so the first unique character wins.",
            evaluationCriteria: [
                "Counts character frequencies (HashMap, LinkedHashMap or int array)",
                "Returns the first unique character in original string order",
                "Returns '_' when there is no unique character",
                "Runs in O(n) time",
            ]),
        JavaChallenge(
            id: "bank-gen-c1", topic: "Generics", difficulty: .hard, type: .explainConcept,
            question: "Explain PECS. When would you declare a parameter as List<? extends T> versus List<? super T>? Give one example of each.",
            expectedAnswer: "Producer Extends, Consumer Super. Use ? extends T when you only read T values out (e.g. sum(List<? extends Number>)). Use ? super T when you only write T values in (e.g. addAll(List<? super Integer>) or Collections.copy's destination).",
            explanation: "Wildcards trade flexibility of the caller's type for restricted operations inside the method.",
            evaluationCriteria: [
                "Explains ? extends is for reading/producing values",
                "Explains ? super is for writing/consuming values",
                "Gives a reasonable example for each",
            ]),
        JavaChallenge(
            id: "bank-exc-c1", topic: "Java exceptions", difficulty: .easy, type: .explainConcept,
            question: "What is the difference between checked and unchecked exceptions in Java? Name one example of each.",
            expectedAnswer: "Checked exceptions (subclasses of Exception but not RuntimeException, e.g. IOException) must be declared or caught at compile time. Unchecked exceptions (RuntimeException and its subclasses, e.g. NullPointerException) are not enforced by the compiler.",
            explanation: "The compiler enforces handling of checked exceptions only.",
            evaluationCriteria: [
                "States that checked exceptions must be caught or declared, enforced at compile time",
                "States that unchecked exceptions extend RuntimeException and are not enforced",
                "Names a correct example of each",
            ]),
    ]
}
