제네릭 : 타입 자체를 파라미터화

<T> : 타입 파라미터

Box<Toy> toyBox; <- BoxofToy

object로 T를 정하면 추후에 문제가 발생할 수 있음.(언제 발생할지 모름. 캐스팅 할때 발생)

매번 명시적으로 캐스팅 해야함.

---

## ❓ 남은 질문

1. 타입 소거(type erasure) 때문에 런타임에 못 하는 대표적인 일은?

   → **답:** 컴파일 후 타입 파라미터가 지워져 `new T[]`, `list instanceof List<String>`, `T.class` 같은 코드가 불가능하다. 런타임에는 `List<String>`과 `List<Integer>`가 모두 `List`로 같아지기 때문이다.

2. PECS(Producer Extends, Consumer Super) 원칙은 언제 `extends`, 언제 `super`를 쓰라는 것인가?

   → **답:** 컬렉션에서 값을 꺼내 읽기(생산)만 하면 `? extends T`, 값을 집어넣기(소비)만 하면 `? super T`를 쓴다. 예를 들어 다른 리스트로 복사할 때 원본은 `extends`, 대상은 `super`가 된다.