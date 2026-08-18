package carve

// 入れた順を覚える Map と Counter。
//
// WhyNot: 標準の map で置き換えられないのは、出力が回る順に依存するため。
// 入れた順が「同点のときどれを選ぶか」を決めている (MostCommon の同点・
// min/max の同点・投票の先着)。map にすると順が散って絵が変わる。

import "sort"

// OMap は入れた順に回る Map。上書きは場所を動かさない。
type OMap[K comparable, V any] struct {
	idx  map[K]int
	keys []K
	vals []V
	live []bool
	n    int
}

// NewOMap は空の dict を作る。
func NewOMap[K comparable, V any]() *OMap[K, V] {
	return &OMap[K, V]{idx: map[K]int{}}
}

// Set は入れる。既にある鍵は値だけ差し替える (並びは変わらない)。
func (m *OMap[K, V]) Set(k K, v V) {
	if i, ok := m.idx[k]; ok && m.live[i] {
		m.vals[i] = v
		return
	}
	m.idx[k] = len(m.keys)
	m.keys = append(m.keys, k)
	m.vals = append(m.vals, v)
	m.live = append(m.live, true)
	m.n++
}

// Get は値を引く。
func (m *OMap[K, V]) Get(k K) (V, bool) {
	if i, ok := m.idx[k]; ok && m.live[i] {
		return m.vals[i], true
	}
	var zero V
	return zero, false
}

// GetOr は無いときに既定値を返す。
func (m *OMap[K, V]) GetOr(k K, def V) V {
	if v, ok := m.Get(k); ok {
		return v
	}
	return def
}

// Has は鍵があるか。
func (m *OMap[K, V]) Has(k K) bool {
	i, ok := m.idx[k]
	return ok && m.live[i]
}

// Delete は消す。残りの並びは変わらない。
func (m *OMap[K, V]) Delete(k K) {
	if i, ok := m.idx[k]; ok && m.live[i] {
		m.live[i] = false
		delete(m.idx, k)
		m.n--
	}
}

// Len は要素数。
func (m *OMap[K, V]) Len() int { return m.n }

// Keys は入れた順の鍵。
func (m *OMap[K, V]) Keys() []K {
	out := make([]K, 0, m.n)
	for i, k := range m.keys {
		if m.live[i] {
			out = append(out, k)
		}
	}
	return out
}

// Items は入れた順の鍵と値。
func (m *OMap[K, V]) Items() ([]K, []V) {
	keys := make([]K, 0, m.n)
	vals := make([]V, 0, m.n)
	for i, k := range m.keys {
		if m.live[i] {
			keys = append(keys, k)
			vals = append(vals, m.vals[i])
		}
	}
	return keys, vals
}

// Counter は鍵ごとの回数を、入れた順を保って数える。
type Counter[K comparable] struct {
	idx    map[K]int
	keys   []K
	counts []int
}

// NewCounter は空の Counter を作る。
func NewCounter[K comparable]() *Counter[K] {
	return &Counter[K]{idx: map[K]int{}}
}

// Add は数える。
func (c *Counter[K]) Add(k K, n int) {
	if i, ok := c.idx[k]; ok {
		c.counts[i] += n
		return
	}
	c.idx[k] = len(c.keys)
	c.keys = append(c.keys, k)
	c.counts = append(c.counts, n)
}

// Get は回数。無ければ 0。
func (c *Counter[K]) Get(k K) int {
	if i, ok := c.idx[k]; ok {
		return c.counts[i]
	}
	return 0
}

// Len は種類の数。
func (c *Counter[K]) Len() int { return len(c.keys) }

// MostCommon は多い順。同点は先に入れた方が先。
//
// WhyNot: 同点を鍵の大小で決めないのは、この順が色への legend 文字の割り当てを
// 決めるため。入れた順の通し番号で並べ替えれば、同点でも先に入れた方が必ず勝つ。
func (c *Counter[K]) MostCommon() ([]K, []int) {
	order := make([]int, len(c.keys))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool {
		return c.counts[order[a]] > c.counts[order[b]]
	})
	keys := make([]K, len(order))
	counts := make([]int, len(order))
	for i, o := range order {
		keys[i], counts[i] = c.keys[o], c.counts[o]
	}
	return keys, counts
}

// MostCommon1 は最も多い 1 つ。同点は先に入れた方。
func (c *Counter[K]) MostCommon1() (K, int, bool) {
	var best K
	bestCount := 0
	found := false
	for i, k := range c.keys {
		if !found || c.counts[i] > bestCount {
			best, bestCount, found = k, c.counts[i], true
		}
	}
	return best, bestCount, found
}
