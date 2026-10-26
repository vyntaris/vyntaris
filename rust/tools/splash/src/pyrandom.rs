pub struct Random {
    mt: [u32; 624],
    index: usize,
}

impl Random {
    pub fn new(seed: u64) -> Random {
        let mut key: Vec<u32> = Vec::new();
        let mut n = seed;
        loop {
            key.push(n as u32);
            n >>= 32;
            if n == 0 {
                break;
            }
        }
        let mut r = Random { mt: [0; 624], index: 624 };
        r.init_genrand(19650218);
        let (mut i, mut j) = (1usize, 0usize);
        for _ in 0..624.max(key.len()) {
            r.mt[i] = (r.mt[i] ^ (r.mt[i - 1] ^ (r.mt[i - 1] >> 30)).wrapping_mul(1664525)).wrapping_add(key[j]).wrapping_add(j as u32);
            i += 1;
            j += 1;
            if i >= 624 {
                r.mt[0] = r.mt[623];
                i = 1;
            }
            if j >= key.len() {
                j = 0;
            }
        }
        for _ in 0..623 {
            r.mt[i] = (r.mt[i] ^ (r.mt[i - 1] ^ (r.mt[i - 1] >> 30)).wrapping_mul(1566083941)).wrapping_sub(i as u32);
            i += 1;
            if i >= 624 {
                r.mt[0] = r.mt[623];
                i = 1;
            }
        }
        r.mt[0] = 0x8000_0000;
        r
    }

    fn init_genrand(&mut self, s: u32) {
        self.mt[0] = s;
        for i in 1..624 {
            self.mt[i] = 1812433253u32.wrapping_mul(self.mt[i - 1] ^ (self.mt[i - 1] >> 30)).wrapping_add(i as u32);
        }
        self.index = 624;
    }

    fn next_u32(&mut self) -> u32 {
        if self.index >= 624 {
            for k in 0..624 {
                let y = (self.mt[k] & 0x8000_0000) | (self.mt[(k + 1) % 624] & 0x7fff_ffff);
                let mut v = self.mt[(k + 397) % 624] ^ (y >> 1);
                if y & 1 != 0 {
                    v ^= 0x9908_b0df;
                }
                self.mt[k] = v;
            }
            self.index = 0;
        }
        let mut y = self.mt[self.index];
        self.index += 1;
        y ^= y >> 11;
        y ^= (y << 7) & 0x9d2c_5680;
        y ^= (y << 15) & 0xefc6_0000;
        y ^ (y >> 18)
    }

    fn bits(&mut self, k: u32) -> u32 {
        self.next_u32() >> (32 - k)
    }

    fn below(&mut self, n: u32) -> u32 {
        let k = 32 - n.leading_zeros();
        loop {
            let r = self.bits(k);
            if r < n {
                return r;
            }
        }
    }

    pub fn randrange(&mut self, n: u32) -> u32 {
        self.below(n)
    }
    pub fn randint(&mut self, a: i64, b: i64) -> i64 {
        a + self.below((b - a + 1) as u32) as i64
    }
    pub fn choice<T: Copy>(&mut self, seq: &[T]) -> T {
        seq[self.below(seq.len() as u32) as usize]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn as_python_has_them() {
        let mut r = Random::new(7);
        let ints: Vec<i64> = (0..5).map(|_| r.randint(2, 4)).collect();
        let (n, c) = (r.randrange(100), r.choice(&['a', 'b', 'c', 'd', 'e', 'f']));
        let want = std::process::Command::new("python3").args(["-c", "import random; r=random.Random(7); print([r.randint(2,4) for _ in range(5)], r.randrange(100), r.choice('abcdef'))"]).output();
        if let Ok(o) = want {
            let got = format!("{ints:?} {n} '{c}'").replace("'", "");
            let py = String::from_utf8_lossy(&o.stdout).trim().replace("'", "");
            if !py.is_empty() {
                assert_eq!(got, py);
            }
        }
    }
}
