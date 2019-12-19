#lang racket

(require racket/dict)

;-- Primitive functions to manipulate objects. ---------------------------------
; Create an object with an arbitrary number of slots.
(define (make-object size)
  (make-vector size null))

; Get the number of slots of an object.
(define (object-size object)
  (vector-length object))

; Retrieve the data held by an object at a specific offset (slot index).
(define (object-ref object offset)
  (vector-ref object offset))

; Mutate the data held by an object at a specific offset.
(define (object-set! object offset value)
  (vector-set! object offset value))

;-------------------------------------------------------------------------------

;-- Primitive function to manipulate any object. -------------------------------
; We set (as a convention) that the name of the class of an object is stored
; at index 0.
(define class-name-offset 0)

; Retrieve the object's class name.
(define (get-object-class-name object)
  (object-ref object class-name-offset))

; Set the object's class name.
(define (set-object-class-name object new-class)
  (object-set! object class-name-offset new-class))

;-------------------------------------------------------------------------------

;-- Primitive functions to manipulate objects representing classes. ------------
; We set (as a convention) that the name of the class is stored at index 1.
; Beware, this is not the same as class-name-offset, indeed, every object
; has a class that it refers to via its name (class-name-offset) but some
; special objects *ARE* classes themselves (so they old their name, stored at
; name-offset).
(define name-offset 1)

; Retrieve the name of a class.
(define (get-class-name class)
  (object-ref class name-offset))

; Set the name of a class.
(define (set-class-name class new-name)
  (object-set! class name-offset new-name))

; We set (as a convention) that the name of the super-class is stored at index
; 2.
(define superclass-name-offset 2)

; Retrieve the name of a class' super-class.
(define (get-class-superclass-name class)
  (object-ref class superclass-name-offset))

; Set the name of a class' super-class.
(define (set-class-superclass-name class new-superclass-name)
  (object-set! class superclass-name-offset new-superclass-name))

; We set (as a convention) that the list of instance variables of a class is
; stored at index 3.
(define instance-variables-offset 3)

; Retrieve the list of instance variables of a class.
(define (get-class-instance-variables class)
  (object-ref class instance-variables-offset))

; Set the list of instance variables of a class.
(define (set-class-instance-variables class new-instance-variables)
  (object-set! class instance-variables-offset new-instance-variables))

; We set (as a convention) that the method dictionary of a class is stored at
; index 4.
(define methods-dictionary-offset 4)

; Retrieve the method dictionary of a class.
(define (get-class-methods-dictionary class)
  (object-ref class methods-dictionary-offset))

; Set the method dictionary of a class.
(define (set-class-methods-dictionary class new-methods-dictionary)
  (object-set! class methods-dictionary-offset new-methods-dictionary))

; Helper function to create a new method dictionary.
; It allows one to not refer to the underlaying datastructure modelling the
; dictionary directly
(define (make-methods-dictionary)
  (make-hash))

; Register a method in the method dictionary of a class.
; In practice, a lambda is provided to be registered in the dictionary with
; the selector as key.
(define (register-method class selector fct)
  (dict-set! (get-class-methods-dictionary class) selector fct))

; Retrieve a method in the method dictionary of a class via its selector.
(define (get-method class selector)
  (dict-ref (get-class-methods-dictionary class) selector))

; Determine if a class defines a method or not via a selector provided as
; parameter.
(define (has-method class selector)
  (dict-has-key? (get-class-methods-dictionary class) selector))

; Helper function to create an unitialized object representing a class.
; It allows one to not hard-code the size of an object representing a class.
(define (make-class)
  (make-object 5))

; Helper function to create a new list of instance variables which is the
; concatenation of the instance variables of a class and an arbitrary list of
; instance variables.
(define (compute-extended-instance-variables superclass new-instance-variables)
  (append (get-class-instance-variables superclass) new-instance-variables))

; Macro to make method definition less verbose.
(define-syntax-rule (add-method class selector arguments method-body)
  (register-method class selector (lambda arguments method-body)))

;-------------------------------------------------------------------------------

;-- Primitive for instance creation --------------------------------------------
; Allocate a new instance of a given class.
; Returns object for which the number of slots is equal to the number of
; instance variables of the class provided as argument.
(define (allocate-new-instance class)
  (let ([instance (make-object (length (get-class-instance-variables class)))])
    (begin
      (set-object-class-name instance (get-class-name class))
      instance)))

;-------------------------------------------------------------------------------

;-- Primitives for classes management ------------------------------------------

(define (make-namespace)
  (make-hash))

(define (register-class namespace class-object)
  (print "Register: ")
  (println (get-class-name class-object))
  (dict-set! namespace (get-class-name class-object) class-object))

(define (get-class namespace symbol)
  (dict-ref namespace symbol))

(define (is-bound? namespace symbol)
  (dict-has-key? namespace symbol))

(define (get-class-or-null namespace symbol)
  (if (is-bound? namespace symbol)
    (get-class namespace symbol)
    null))

;-------------------------------------------------------------------------------

;-- Macro magic for being able to refer to self easily -------------------------
; When we encounter self variable, we expand it as (bound-self).
; (bound-self) is a parameter that is bound to the object on which is called a
; method.
(define-syntax self
    (lambda (stx)
      (syntax-case stx ()
        [val (identifier? (syntax self)) (syntax (bound-self))])))

(define bound-self (make-parameter null))

;-------------------------------------------------------------------------------

;-- Helper methods to manipulate objects ---------------------------------------

(define (get-object-class object namespace)
  (get-class namespace (get-object-class-name object)))

(define (get-object-superclass object namespace)
  (get-class namespace (get-class-superclass-name (get-object-class object namespace))))

(define (set-instance-variable-value object instance-variable-name value namespace)
  (object-set!
    object
    (index-of (get-class-instance-variables (get-object-class object namespace)) instance-variable-name)
    value))

(define (get-instance-variable-value object instance-variable-name namespace)
  (object-ref
    object
    (index-of (get-class-instance-variables (get-object-class object namespace)) instance-variable-name)))

;-- Primitives for sending messages --------------------------------------------

(define (lookup selector class namespace)
  (if (has-method class selector)
      (get-method class selector)
      (if (eq? (get-class-name class) 'Object)
          null
          (lookup selector (get-class namespace (get-class-superclass-name class)) namespace))))

(define (send receiver selector arguments namespace [super? #f])
  (let
    ([lookup-start
      (if super? (get-object-superclass receiver namespace) (get-object-class receiver namespace))])
    (parameterize
      ([bound-self receiver])
      (apply (lookup selector lookup-start namespace) arguments))))

(define (super-send receiver selector arguments namespace)
  (send receiver selector arguments namespace true))

;-------------------------------------------------------------------------------

;-- Bootstraping the kernel ----------------------------------------------------

(define (build-Class-initialize Class namespace)
  (add-method Class 'initialize ()
    (let (
      [superclass-or-null (get-class-or-null namespace (get-class-superclass-name self))])
      (begin
        (if (null? superclass-or-null)
            (set-class-instance-variables
               self
               (append '(class) (get-class-instance-variables self)))
            (set-class-instance-variables
               self
               (compute-extended-instance-variables
                 superclass-or-null
                 (get-class-instance-variables self))))
        (set-class-methods-dictionary self (make-methods-dictionary))
        self))))

(define (build-Class-new Class namespace)
  (add-method Class 'new ()
    (send (send self 'allocate '() namespace) 'initialize '() namespace)))

(define (build-Class-allocate Class namespace)
  (add-method Class 'allocate ()
      (allocate-new-instance self)))

(define (manually-build-Class namespace)
  (let ([Class (make-class)])
    (set-object-class-name Class 'Class)
    (set-class-name Class 'Class)
    (set-class-superclass-name Class 'Object)
    (set-class-instance-variables Class '(class name superclass iv methodDict))
    (set-class-methods-dictionary Class (make-methods-dictionary))
    (register-class namespace Class)
    (build-Class-initialize (get-class namespace 'Class) namespace)
    (build-Class-new (get-class namespace 'Class) namespace)
    (build-Class-allocate (get-class namespace 'Class) namespace)
    Class))

(define (build-Object namespace)
  (let ([Object (send (get-class namespace 'Class) 'new '() namespace)])
    (begin
      (set-instance-variable-value Object 'name 'Object namespace)
      (register-class namespace Object) ; Register Object class in namespace ASAP. ;-)
      (set-instance-variable-value Object 'iv '(class) namespace)
      (add-method Object 'initialize ()
        self)
      (add-method Object 'class ()
        (get-object-class self))
      (add-method Object 'isClass ()
        false)
      (add-method Object 'isMetaclass ()
        false)
      Object))) ; TODO: add 'doesNotUnderstand: method

(define (build-Class namespace)
  (let ([Class (send (get-class namespace 'Class) 'new '() namespace)])
    (begin
      (set-instance-variable-value Class 'name 'Class namespace)
      (set-instance-variable-value Class 'superclass 'Object namespace)
      (set-instance-variable-value Class 'iv '(class name superclass iv methodDict) namespace)
      (set-instance-variable-value Class 'methodDict (make-methods-dictionary) namespace)
      (build-Class-new Class namespace)
      (build-Class-allocate Class namespace)
      (add-method Class 'initialize ()
        (begin
          (super-send self 'initialize '() namespace)
          (set-class-instance-variables
               self
               (compute-extended-instance-variables
                 (get-class namespace (get-class-superclass-name self))
                 (get-class-instance-variables self)))
          (set-class-methods-dictionary self (make-methods-dictionary))
          self))
      (add-method Class 'newNamed:superclassName:instanceVariables: (className superclassName instanceVariableNames)
        (let
          ([newClass (send self 'allocate '() namespace)])
          (set-instance-variable-value newClass 'name className namespace)
          (set-instance-variable-value newClass 'superclass superclassName namespace)
          (set-instance-variable-value newClass 'iv instanceVariableNames namespace)
          (send newClass 'initialize '() namespace)))
      (register-class namespace Class) ; Register Class class in namespace.
      Class)))

(define (build-kernel)
  (let
    ([namespace (make-namespace)])
    (manually-build-Class namespace) ; Here we create the egg out of nowhere...
    (build-Object namespace) ; ...so we can get the chicken...
    (build-Class namespace) ; ...that can produce a true egg to replace the hand-made one. :-)
    namespace))

;-------------------------------------------------------------------------------

;-- Playground -----------------------------------------------------------------
(define namespace (build-kernel))
(define Class (get-class namespace 'Class))
(define Object (get-class namespace 'Object))

(define Point (send Class 'newNamed:superclassName:instanceVariables: '(Point Object (x y)) namespace))
(register-class namespace Point)

(add-method Point 'x ()
  (get-instance-variable-value self 'x namespace))

(add-method Point 'y ()
  (get-instance-variable-value self 'y namespace))

(add-method Point 'y: (y)
  (begin
    (set-instance-variable-value self 'y y namespace)
    self))

(add-method Point 'x: (x)
  (begin
    (set-instance-variable-value self 'x x namespace)
    self))

(define point-instance (send Point 'new '() namespace))
(send point-instance 'x: '(1) namespace)
(send point-instance 'y: '(2) namespace)
(send point-instance 'x '() namespace)
(send point-instance 'y '() namespace)

;-------------------------------------------------------------------------------

; Tests, to move in a separated file -------------------------------------------

(require rackunit)

(define-test-suite object-kernel
  (test-case "test-make-object"
    (check-equal? (make-object 5) (vector null null null null null))
  )
  (test-case "test-object-size"
    (check-equal? (object-size (make-object 5)) 5)
  )
  (test-case "test-object-ref-set!"
    (let ([o (make-object 3)])
      (check-equal? (object-ref o 0) null)
      (check-equal? (object-ref o 1) null)
      (check-equal? (object-ref o 2) null)
      (object-set! o 1 42)
      (check-equal? (object-ref o 0) null)
      (check-equal? (object-ref o 1) 42)
      (check-equal? (object-ref o 2) null))
  )

  (test-case "test-get-set-object-class-name"
    (let ([o (make-object 2)])
      (check-equal? (get-object-class-name o) null)
      (set-object-class-name o 'Object)
      (check-equal? (get-object-class-name o) 'Object)))

  (test-case "test-get-set-class-name"
    (let ([class (make-class)])
      (check-equal? (get-class-name class) null)
      (set-class-name class 'Point)
      (check-equal? (get-class-name class) 'Point)))

  (test-case "test-get-set-class-superclass-name"
    (let ([class (make-class)])
      (check-equal? (get-class-superclass-name class) null)
      (set-class-superclass-name class 'Object)
      (check-equal? (get-class-superclass-name class) 'Object)))

  (test-case "test-get-set-class-instance-variables"
    (let ([class (make-class)])
      (check-equal? (get-class-instance-variables class) null)
      (set-class-instance-variables class '(x y))
      (check-equal? (get-class-instance-variables class) '(x y))))
  
  (test-case "test-get-set-class-methods-dictionary"
    (let (
          [class (make-class)]
          [methods-dict (make-methods-dictionary)])
      (check-equal? (get-class-methods-dictionary class) null)
      (set-class-methods-dictionary class methods-dict)
      (check-equal? (get-class-methods-dictionary class) methods-dict)))

  (test-case "test-register-method-has-method-get-method"
    (let (
          [class (make-class)]
          [methods-dict (make-methods-dictionary)]
          [method-lambda (lambda () 42)])
      (set-class-methods-dictionary class methods-dict)
      (check-false (has-method class 'foo))
      (register-method class 'foo method-lambda)
      (check-equal? (get-method class 'foo) method-lambda)))

  (test-case "test-allocate-new-instance"
    (let ([hand-made-class (make-class)])
      (set-class-instance-variables hand-made-class '(class x y))
      (check-equal? (object-size (allocate-new-instance hand-made-class)) 3)))

  (test-case "test-compute-extended-instance-variables"
    (let ([hand-made-class (make-class)])
      (set-class-instance-variables hand-made-class '(class x y))
      (check-equal? (compute-extended-instance-variables hand-made-class '(z)) '(class x y z))))
)

(require rackunit/text-ui)
(run-tests object-kernel)