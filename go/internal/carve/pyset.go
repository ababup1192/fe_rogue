package carve

// CPython の set を、回る順まで含めて同じに動かす。
//
// WhyNot: Go の map で置き換えられないのは、この道具が set を回った順で
// ボクセルを積み、その順が最後まで残るため:
//   - carve() の `for x in xs: for z in zs` が立体の並びを決める
//   - その並びが「同じ (x,y) にどの z を残すか」「動いた画素が重なったときどれが勝つか」を決める
// Go の map はわざと順を散らすので、写すには CPython の表の並び方そのものが要る。
//
// 表の作り: 大きさ 8 から始め、埋まりが 3/5 を越えると (要素数 × 4) を越える
// 最小の 2 冪へ作り直す。位置は hash & mask から始めて、隣を 9 個まで見て、
// 外れたら i = i*5 + 1 + (perturb >>= 5) で跳ぶ。

const (
	setMinSize   = 8
	linearProbes = 9
	perturbShift = 5
)

type setSlot[K comparable] struct {
	used  bool
	dummy bool
	hash  uint64
	key   K
}

// PySet は CPython の set。
type PySet[K comparable] struct {
	table  []setSlot[K]
	mask   uint64
	fill   int
	used   int
	finger uint64
	hashOf func(K) uint64
}

// NewPySet は空の set を作る。
func NewPySet[K comparable](hashOf func(K) uint64) *PySet[K] {
	return &PySet[K]{
		table:  make([]setSlot[K], setMinSize),
		mask:   setMinSize - 1,
		hashOf: hashOf,
	}
}

// NewPySetFromKeys は Python の set(dict) と同じ作り方をする。
//
// WhyNot: 1 つずつ Add しないのは、CPython が dict から作るときだけ
// 最初に (要素数 × 2) を越える大きさへ広げてから入れるため。表の大きさが
// 違うと入る場所が変わり、回る順が変わる。
func NewPySetFromKeys[K comparable](keys []K, hashOf func(K) uint64) *PySet[K] {
	s := NewPySet(hashOf)
	if (0+len(keys))*5 >= int(s.mask)*3 {
		s.resize(len(keys) * 2)
	}
	for _, k := range keys {
		s.Add(k)
	}
	return s
}

func (s *PySet[K]) empty(i uint64) bool {
	e := &s.table[i]
	return !e.used && !e.dummy
}

// Add は入れる。
func (s *PySet[K]) Add(k K) {
	h := s.hashOf(k)
	mask := s.mask
	i := h & mask
	if s.empty(i) {
		s.foundUnused(i, k, h)
		return
	}
	freeslot := -1
	perturb := h
	for {
		e := &s.table[i]
		if e.used && e.hash == h && e.key == k {
			return
		}
		if e.dummy {
			freeslot = int(i)
		}
		if i+linearProbes <= mask {
			for j := uint64(1); j <= linearProbes; j++ {
				p := i + j
				e2 := &s.table[p]
				if !e2.used && !e2.dummy {
					s.foundUnusedOrDummy(p, freeslot, k, h)
					return
				}
				if e2.used && e2.hash == h && e2.key == k {
					return
				}
				if e2.dummy {
					freeslot = int(p)
				}
			}
		}
		perturb >>= perturbShift
		i = (i*5 + 1 + perturb) & mask
		if s.empty(i) {
			s.foundUnusedOrDummy(i, freeslot, k, h)
			return
		}
	}
}

func (s *PySet[K]) foundUnusedOrDummy(i uint64, freeslot int, k K, h uint64) {
	if freeslot < 0 {
		s.foundUnused(i, k, h)
		return
	}
	s.used++
	e := &s.table[freeslot]
	e.used, e.dummy, e.key, e.hash = true, false, k, h
}

func (s *PySet[K]) foundUnused(i uint64, k K, h uint64) {
	s.fill++
	s.used++
	e := &s.table[i]
	e.used, e.dummy, e.key, e.hash = true, false, k, h
	if s.fill*5 < int(s.mask)*3 {
		return
	}
	if s.used > 50000 {
		s.resize(s.used * 2)
	} else {
		s.resize(s.used * 4)
	}
}

func (s *PySet[K]) resize(minused int) {
	newsize := uint64(setMinSize)
	for newsize <= uint64(minused) {
		newsize <<= 1
	}
	old := s.table
	s.table = make([]setSlot[K], newsize)
	s.mask = newsize - 1
	s.fill = s.used
	for i := range old {
		if old[i].used {
			s.insertClean(old[i].key, old[i].hash)
		}
	}
}

func (s *PySet[K]) insertClean(k K, h uint64) {
	mask := s.mask
	perturb := h
	i := h & mask
	for {
		if !s.table[i].used {
			s.table[i].used, s.table[i].key, s.table[i].hash = true, k, h
			return
		}
		if i+linearProbes <= mask {
			for j := uint64(1); j <= linearProbes; j++ {
				p := i + j
				if !s.table[p].used {
					s.table[p].used, s.table[p].key, s.table[p].hash = true, k, h
					return
				}
			}
		}
		perturb >>= perturbShift
		i = (i*5 + 1 + perturb) & mask
	}
}

func (s *PySet[K]) lookup(k K) (uint64, bool) {
	h := s.hashOf(k)
	mask := s.mask
	i := h & mask
	if s.empty(i) {
		return 0, false
	}
	perturb := h
	for {
		e := &s.table[i]
		if e.used && e.hash == h && e.key == k {
			return i, true
		}
		if i+linearProbes <= mask {
			for j := uint64(1); j <= linearProbes; j++ {
				p := i + j
				e2 := &s.table[p]
				if !e2.used && !e2.dummy {
					return 0, false
				}
				if e2.used && e2.hash == h && e2.key == k {
					return p, true
				}
			}
		}
		perturb >>= perturbShift
		i = (i*5 + 1 + perturb) & mask
		if s.empty(i) {
			return 0, false
		}
	}
}

// Contains は入っているか。
func (s *PySet[K]) Contains(k K) bool {
	_, ok := s.lookup(k)
	return ok
}

// Remove は取り除く。
func (s *PySet[K]) Remove(k K) {
	i, ok := s.lookup(k)
	if !ok {
		return
	}
	s.table[i].used, s.table[i].dummy = false, true
	s.used--
}

// Pop は 1 つ取り出す。前回の続きの場所から表を舐める。
func (s *PySet[K]) Pop() (K, bool) {
	var zero K
	if s.used == 0 {
		return zero, false
	}
	i := s.finger & s.mask
	for {
		if s.table[i].used {
			break
		}
		i++
		if i > s.mask {
			i = 0
		}
	}
	k := s.table[i].key
	s.table[i].used, s.table[i].dummy = false, true
	s.used--
	s.finger = i + 1
	return k, true
}

// Len は要素数。
func (s *PySet[K]) Len() int { return s.used }

// Items は表の並びのまま返す (Python の for が回る順)。
func (s *PySet[K]) Items() []K {
	out := make([]K, 0, s.used)
	for i := range s.table {
		if s.table[i].used {
			out = append(out, s.table[i].key)
		}
	}
	return out
}

// hashInt は Python の hash(int)。
func hashInt(v int) uint64 {
	if v == -1 {
		v = -2
	}
	return uint64(int64(v))
}

// hashPt は Python 3.7 の hash((x, y))。
//
// WhyNot: 3.8 以降の xxHash 版で書かないのは、この道具を動かしている python3 が
// 3.7 で、3.8 とは組の hash が違うため。表の並びが変わると出る絵が変わる。
func hashPt(p Pt) uint64 {
	x := uint64(0x345678)
	mult := uint64(1000003)
	items := [2]int{p.X, p.Y}
	l := uint64(2)
	for _, v := range items {
		l--
		x = (x ^ hashInt(v)) * mult
		mult += 82520 + l + l
	}
	x += 97531
	if x == ^uint64(0) {
		x = ^uint64(0) - 1
	}
	return x
}
