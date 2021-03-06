
/- Formalization of floating-point numbers, using the Flocq library. -/

import .integers .lib .flocq .archi

namespace floats
open integers flocq word

/- Boolean-valued comparisons -/

def cmp_of_comparison : comparison → option ordering → bool
| Ceq (some ordering.eq) := tt
| Ceq _                  := ff
| Cne (some ordering.eq) := ff
| Cne _                  := tt
| Clt (some ordering.lt) := tt
| Clt _                  := ff
| Cle (some ordering.lt) := tt
| Cle (some ordering.eq) := tt
| Cle _                  := ff
| Cgt (some ordering.gt) := tt
| Cgt _                  := ff
| Cge (some ordering.gt) := tt
| Cge (some ordering.eq) := tt
| Cge _                  := ff

lemma cmp_of_comparison_swap (c x) :
  cmp_of_comparison (swap_comparison c) x =
  cmp_of_comparison c (ordering.swap <$> x) := sorry'

lemma cmp_of_comparison_ne_eq (x) :
  cmp_of_comparison Cne x = bnot (cmp_of_comparison Ceq x) := sorry'

lemma cmp_of_comparison_lt_not_eq (x) :
  cmp_of_comparison Clt x → ¬ cmp_of_comparison Ceq x := sorry'

lemma cmp_of_comparison_le_lt_eq (x) :
  cmp_of_comparison Cle x = cmp_of_comparison Clt x || cmp_of_comparison Ceq x := sorry'

lemma cmp_of_comparison_gt_not_eq (x) :
  cmp_of_comparison Cgt x → ¬ cmp_of_comparison Ceq x := sorry'

lemma cmp_of_comparison_ge_gt_eq (x) :
  cmp_of_comparison Cge x = cmp_of_comparison Cgt x || cmp_of_comparison Ceq x := sorry'

lemma cmp_of_comparison_lt_not_gt (x) :
  cmp_of_comparison Clt x → ¬ cmp_of_comparison Cgt x := sorry'

def float : Type := sorry' /- the type of IEE754 double-precision FP numbers -/
def float32 : Type := sorry' /- the type of IEE754 single-precision FP numbers -/

/- * Double-precision FP numbers -/

namespace float

/- ** NaN payload manipulations -/

/- The following definitions are not part of the IEEE754 standard but
    apply to all architectures supported by CompCert. -/

/- Transform a Nan payload to a quiet Nan payload. -/

def transform_quiet_pl (pl : nan_pl 53) : nan_pl 53 :=
word.or pl (word.repr (2^22))

lemma transform_quiet_pl_idempotent (pl) :
  transform_quiet_pl (transform_quiet_pl pl) = transform_quiet_pl pl := sorry'

/- Nan payload operations for single <-> double conversions. -/

def expand_pl (pl : nan_pl 24) : nan_pl 53 :=
word.shl (ucoe pl) (repr 29)

def of_single_pl (s : bool) (pl : nan_pl 24) : bool × nan_pl 53 :=
(s, if archi.float_of_single_preserves_sNaN
    then expand_pl pl
    else transform_quiet_pl (expand_pl pl))

def reduce_pl (pl : nan_pl 53) : nan_pl 24 :=
ucoe (word.shr pl (repr 29))

def to_single_pl (s : bool) (pl : nan_pl 53) : bool × nan_pl 24 :=
(s, reduce_pl (transform_quiet_pl pl))

/- NaN payload operations for opposite and absolute value. -/

def neg_pl (s : bool) (pl : nan_pl 53) := (bnot s, pl)
def abs_pl (s : bool) (pl : nan_pl 53) := (ff, pl)

/- The NaN payload operations for two-argument arithmetic operations
   are not part of the IEEE754 standard, but all architectures of
   Compcert share a similar NaN behavior, parameterized by:
- a "default" payload which occurs when an operation generates a NaN from
  non-NaN arguments;
- a choice function determining which of the payload arguments to choose,
  when an operation is given two NaN arguments. -/

def binop_pl (x y : binary64) : bool × nan_pl 53 := sorry'

/- ** Operations over double-precision floats -/

def zero : float := sorry' /- the float [+0.0] -/

instance : has_zero float := ⟨zero⟩

instance eq_dec : decidable_eq float := sorry'

/- Arithmetic operations -/

protected def neg : float → float := sorry' /- opposite (change sign) -/
def abs : float → float := sorry' /- absolute value (set sign to [+]) -/
protected def add : float → float → float := sorry' /- addition -/
protected def sub : float → float → float := sorry' /- subtraction -/
protected def mul : float → float → float := sorry' /- multiplication -/
protected def div : float → float → float := sorry' /- division -/
def cmp (c:comparison) (f1 f2 : float) : bool := /- comparison -/
cmp_of_comparison c sorry'

instance : has_add float := ⟨float.add⟩
instance : has_neg float := ⟨float.neg⟩
instance : has_sub float := ⟨float.sub⟩
instance : has_mul float := ⟨float.mul⟩
instance : has_div float := ⟨float.div⟩

/- Conversions -/

def of_single : float32 → float := sorry'
def to_single : float → float32 := sorry'

def to_int (f:float) : option int32 := /- conversion to signed 32-bit int -/
repr <$> sorry'
def to_intu (f:float) : option int32 := /- conversion to unsigned 32-bit int -/
repr <$> sorry'
def to_long (f:float) : option int64 := /- conversion to signed 64-bit int -/
repr <$> sorry'
def to_longu (f:float) : option int64 := /- conversion to unsigned 64-bit int -/
repr <$> sorry'

def of_int (n:int32) : float := /- conversion from signed 32-bit int -/
sorry'
def of_intu (n:int32) : float:= /- conversion from unsigned 32-bit int -/
sorry'

def of_long (n:int64) : float := /- conversion from signed 64-bit int -/
sorry'
def of_longu (n:int64) : float:= /- conversion from unsigned 64-bit int -/
sorry'

instance coe_int32_float : has_coe int32 float := ⟨of_int⟩
instance coe_int64_float : has_coe int64 float := ⟨of_long⟩

def from_parsed (base : pos_num) (intPart : pos_num) (expPart : ℤ) : float :=
sorry'

/- Conversions between floats and their concrete in-memory representation
    as a sequence of 64 bits. -/

def to_bits (f : float) : int64 := sorry'
def of_bits (b : int64) : float := sorry'

def from_words (hi lo : int32) : float := of_bits (int64.ofwords hi lo)

def is_nan : float → bool := sorry'

/- ** Properties -/

/- Below are the only properties of floating-point arithmetic that we
  rely on in the compiler proof. -/

/- Commutativity properties of addition and multiplication. -/

theorem add_comm (x y) : ¬ is_nan x ∨ ¬ is_nan y → x + y = y + x := sorry'

theorem mul_comm (x y) : ¬ is_nan x ∨ ¬ is_nan y → x * y = y * x := sorry'

/- Multiplication by 2 is diagonal addition. -/

theorem mul2_add (f) : f + f = f * of_int 2 := sorry'

/- Divisions that can be turned into multiplication by an inverse. -/

def exact_inverse : float → option float := sorry'

theorem div_mul_inverse (x y z) : exact_inverse y = some z → x / y = x * z := sorry'

/- Properties of comparisons. -/

lemma cmp_swap (c x y) : cmp (swap_comparison c) x y = cmp c y x := sorry'

lemma cmp_ne_eq (x y) : cmp Cne x y = bnot (cmp Ceq x y) := sorry'

lemma cmp_lt_not_eq (x y) : cmp Clt x y → ¬ cmp Ceq x y := sorry'

lemma cmp_le_lt_eq (x y) : cmp Cle x y = cmp Clt x y || cmp Ceq x y := sorry'

lemma cmp_gt_not_eq (x y) : cmp Cgt x y → ¬ cmp Ceq x y := sorry'

lemma cmp_ge_gt_eq (x y) : cmp Cge x y = cmp Cgt x y || cmp Ceq x y := sorry'

lemma cmp_lt_not_gt (x y) : cmp Clt x y → ¬ cmp Cgt x y := sorry'

/- Properties of conversions to/from in-memory representation.
  The conversions are bijective (one-to-one). -/

theorem of_to_bits (f) : of_bits (to_bits f) = f := sorry'

theorem to_of_bits (b) : to_bits (of_bits b) = b := sorry'

/- Conversions between floats and unsigned ints can be defined
  in terms of conversions between floats and signed ints.
  (Most processors provide only the latter, forcing the compiler
  to emulate the former.)   -/

def half32 : int32 := repr (@min_signed W32).  /- [0x8000_0000] -/

theorem of_intu_of_int_1 (x) : word.ltu x half32 → of_intu x = of_int x := sorry'

theorem of_intu_of_int_2 (x) : ¬ word.ltu x half32 → of_intu x = of_int (x - half32) + of_intu half32 := sorry'

theorem to_intu_to_int_1 (x n) : cmp Clt x (of_intu half32) → to_intu x = some n → to_int x = some n := sorry'

theorem to_intu_to_int_2 (x n) : ¬ cmp Clt x (of_intu half32) → to_intu x = some n →
  to_int (x - of_intu half32) = some (n - half32) := sorry'

/- Conversions from ints to floats can be defined as bitwise manipulations
  over the in-memory representation.  This is what the PowerPC port does.
  The trick is that [from_words 0x4330_0000 x] is the float
  [2^52 + of_intu x]. -/

def bit433 : int32 := repr 0x43300000

lemma split_bits_or (x) :
  split_bits 52 11 (unsigned (int64.ofwords bit433 x)) = (ff, unsigned x, 1075) := sorry'

theorem of_intu_from_words (x) :
  of_intu x = from_words bit433 x - from_words bit433 0 := sorry'

lemma half32_signed_unsigned (x) :
  (unsigned (x + half32) : ℤ) = signed x + @half_modulus W32 := sorry'

theorem of_int_from_words (x) :
  of_int x = from_words bit433 (x + half32) - from_words bit433 half32 := sorry'

def bit453 : int32 := repr 0x45300000

lemma split_bits_or' (x) :
  split_bits 52 11 (unsigned (int64.ofwords bit453 x)) = (ff, unsigned x, 1107) := sorry'

theorem of_longu_from_words (l) : of_longu l =
  from_words bit453 (int64.hiword l) -
  from_words bit453 (repr (2^20)) +
  from_words bit433 (int64.loword l) := sorry'

theorem of_long_from_words (l) : of_long l =
    from_words bit453 (int64.hiword l + half32) -
    from_words bit453 (repr (2^20+2^31)) +
    from_words bit433 (int64.loword l) := sorry'

/- Conversions from unsigned longs can be expressed in terms of conversions from signed longs.
    If the unsigned long is too big, a round-to-odd must be performed on it
    to avoid double rounding. -/

theorem of_longu_of_long_1 (x) :
  word.ltu x (repr (@half_modulus W64)) →
  of_longu x = of_long x := sorry'

theorem of_longu_of_long_2 (x) :
  ¬ word.ltu x (repr (@half_modulus W64)) →
  of_longu x = of_long (word.or (word.shru x 1) (word.and x 1)) * of_int (repr 2) := sorry'

end float

/- * Single-precision FP numbers -/

namespace float32

/- ** NaN payload manipulations -/

def transform_quiet_pl (pl : nan_pl 24) : nan_pl 24 :=
word.or pl (repr (2^22))

lemma transform_quiet_pl_idempotent (pl) :
  transform_quiet_pl (transform_quiet_pl pl) = transform_quiet_pl pl := sorry'

def neg_pl (s:bool) (pl:nan_pl 24) := (bnot s, pl)
def abs_pl (s:bool) (pl:nan_pl 24) := (ff, pl)

def binop_pl (x y : binary32) : bool × nan_pl 24 := sorry'

/- ** Operations over single-precision floats -/

def zero : float32 := sorry' /- the float [+0.0] -/

instance : has_zero float32 := ⟨zero⟩

instance eq_dec : decidable_eq float32 := sorry'

/- Arithmetic operations -/

protected def neg : float32 → float32 := sorry' /- opposite (change sign) -/
def abs : float32 → float32 := sorry' /- absolute value (set sign to [+]) -/
protected def add : float32 → float32 → float32 := sorry' /- addition -/
protected def sub : float32 → float32 → float32 := sorry' /- subtraction -/
protected def mul : float32 → float32 → float32 := sorry' /- multiplication -/
protected def div : float32 → float32 → float32 := sorry' /- division -/
def cmp (c:comparison) (f1 f2 : float32) : bool := /- comparison -/
cmp_of_comparison c sorry'

instance : has_add float32 := ⟨float32.add⟩
instance : has_neg float32 := ⟨float32.neg⟩
instance : has_sub float32 := ⟨float32.sub⟩
instance : has_mul float32 := ⟨float32.mul⟩
instance : has_div float32 := ⟨float32.div⟩

/- Conversions -/

def of_double : float → float32 := float.to_single
def to_double : float32 → float := float.of_single

def to_int (f:float32) : option int32 := /- conversion to signed 32-bit int -/
repr <$> sorry'
def to_intu (f:float32) : option int32 := /- conversion to unsigned 32-bit int -/
repr <$> sorry'
def to_long (f:float32) : option int64 := /- conversion to signed 64-bit int -/
repr <$> sorry'
def to_longu (f:float32) : option int64 := /- conversion to unsigned 64-bit int -/
repr <$> sorry'

def of_int (n:int32) : float32 := /- conversion from signed 32-bit int to single-precision float -/
sorry'
def of_intu (n:int32) : float32 := /- conversion from unsigned 32-bit int to single-precision float -/
sorry'

def of_long (n:int64) : float32 := /- conversion from signed 64-bit int to single-precision float -/
sorry'
def of_longu (n:int64) : float32 := /- conversion from unsigned 64-bit int to single-precision float -/
sorry'

def from_parsed (base : pos_num) (intPart : pos_num) (expPart : ℤ) : float32 :=
sorry'

/- Conversions between floats and their concrete in-memory representation
    as a sequence of 32 bits. -/

def to_bits (f : float32) : int32 := sorry'
def of_bits (b : int32) : float32 := sorry'

def is_nan : float32 → bool := sorry'

/- ** Properties -/

/- Commutativity properties of addition and multiplication. -/

theorem add_comm (x y) : ¬ is_nan x ∨ ¬ is_nan y → x + y = y + x := sorry'

theorem mul_comm (x y) : ¬ is_nan x ∨ ¬ is_nan y → x * y = y * x := sorry'

/- Multiplication by 2 is diagonal addition. -/

theorem mul2_add (f) : f + f = f * of_int 2 := sorry'

/- Divisions that can be turned into multiplication by an inverse. -/

def exact_inverse : float32 → option float32 := sorry'

theorem div_mul_inverse (x y z) : exact_inverse y = some z → x / y = x * z := sorry'

/- Properties of comparisons. -/

lemma cmp_swap (c x y) : cmp (swap_comparison c) x y = cmp c y x := sorry'

lemma cmp_ne_eq (x y) : cmp Cne x y = bnot (cmp Ceq x y) := sorry'

lemma cmp_lt_not_eq (x y) : cmp Clt x y → ¬ cmp Ceq x y := sorry'

lemma cmp_le_lt_eq (x y) : cmp Cle x y = cmp Clt x y || cmp Ceq x y := sorry'

lemma cmp_gt_not_eq (x y) : cmp Cgt x y → ¬ cmp Ceq x y := sorry'

lemma cmp_ge_gt_eq (x y) : cmp Cge x y = cmp Cgt x y || cmp Ceq x y := sorry'

lemma cmp_lt_not_gt (x y) : cmp Clt x y → ¬ cmp Cgt x y := sorry'

theorem cmp_double (f1 f2 c) : cmp c f1 f2 = float.cmp c (to_double f1) (to_double f2) := sorry'

/- Properties of conversions to/from in-memory representation.
  The conversions are bijective (one-to-one). -/

theorem of_to_bits (f) : of_bits (to_bits f) = f := sorry'

theorem to_of_bits (b) : to_bits (of_bits b) = b := sorry'

/- Conversions from 32-bit integers to single-precision floats can
  be decomposed into a conversion to a double-precision float,
  followed by a [Float32.of_double] conversion.  No double rounding occurs. -/

theorem of_int_double (n) : of_int n = of_double (float.of_int n) := sorry'

theorem of_intu_double (n) : of_intu n = of_double (float.of_intu n) := sorry'

/- Conversion of single-precision floats to integers can be decomposed
  into a [Float32.to_double] extension, followed by a double-precision-to-int
  conversion. -/

theorem to_int_double (f n) : to_int f = some n → float.to_int (to_double f) = some n := sorry'

theorem to_intu_double (f n) : to_intu f = some n → float.to_intu (to_double f) = some n := sorry'

theorem to_long_double (f n) : to_long f = some n → float.to_long (to_double f) = some n := sorry'

theorem to_longu_double (f n) : to_longu f = some n → float.to_longu (to_double f) = some n := sorry'

/- Conversions from 64-bit integers to single-precision floats can be expressed
  as conversion to a double-precision float followed by a [Float32.of_double] conversion.
  To avoid double rounding when the integer is large (above [2^53]), a round
  to odd must be performed on the integer before conversion to double-precision float. -/

lemma int_round_odd_plus (p n) :
  int_round_odd n p = int.land (int.lor n (int.land n (2^p-1) + (2^p-1))) (-(2^p)) := sorry'

theorem of_longu_double_1 (n) : unsigned n ≤ 2^53 →
  of_longu n = of_double (float.of_longu n) := sorry'

theorem of_longu_double_2 (n) : 2^36 ≤ unsigned n →
  of_longu n = of_double (float.of_longu $
    word.and (word.or n (word.and n (repr 2047) + repr 2047)) (repr (-2048))) := sorry'

theorem of_long_double_1 (n) : (signed n).nat_abs ≤ 2^53 →
  of_long n = of_double (float.of_long n) := sorry'

theorem of_long_double_2 (n) : 2^36 ≤ (signed n).nat_abs →
  of_long n = of_double (float.of_long $
    word.and (word.or n (word.and n (repr 2047) + repr 2047)) (repr (-2048))) := sorry'

end float32

end floats
