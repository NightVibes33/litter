//! Rivest–Shamir–Adleman (RSA) private keys.

use crate::{public::RsaPublicKey, Error, Mpint, Result};
use core::fmt::{self, Debug};
use ctutils::{Choice, CtEq};
use encoding::{CheckedSum, Decode, Encode, Reader, Writer};
use zeroize::Zeroize;

#[cfg(feature = "rsa")]
use alloc::{boxed::Box, vec::Vec};
#[cfg(feature = "rsa")]
use rand_core::CryptoRng;

/// RSA private key.
#[derive(Clone)]
pub struct RsaPrivateKey {
    /// RSA private exponent.
    d: Mpint,

    /// CRT coefficient: `(inverse of q) mod p`.
    iqmp: Mpint,

    /// First prime factor of `n`.
    p: Mpint,

    /// Second prime factor of `n`.
    q: Mpint,
}

impl RsaPrivateKey {
    /// Create a new RSA private key with the following components:
    ///
    /// - `d`: RSA private exponent.
    /// - `iqmp`: CRT coefficient: `(inverse of q) mod p`.
    /// - `p`: First prime factor of `n`.
    /// - `q`: Second prime factor of `n`.
    ///
    /// # Errors
    /// Returns [`Error::FormatEncoding`] if any of the provided values are negative.
    pub fn new(d: Mpint, iqmp: Mpint, p: Mpint, q: Mpint) -> Result<Self> {
        if d.is_positive() && iqmp.is_positive() && p.is_positive() && q.is_positive() {
            Ok(Self { d, iqmp, p, q })
        } else {
            Err(Error::FormatEncoding)
        }
    }

    /// RSA private exponent.
    #[must_use]
    pub fn d(&self) -> &Mpint {
        &self.d
    }

    /// CRT coefficient: `(inverse of q) mod p`.
    #[must_use]
    pub fn iqmp(&self) -> &Mpint {
        &self.iqmp
    }

    /// First prime factor of `n`.
    #[must_use]
    pub fn p(&self) -> &Mpint {
        &self.p
    }

    /// Second prime factor of `n`.
    #[must_use]
    pub fn q(&self) -> &Mpint {
        &self.q
    }
}

impl CtEq for RsaPrivateKey {
    fn ct_eq(&self, other: &Self) -> Choice {
        self.d.ct_eq(&other.d)
            & self.iqmp.ct_eq(&self.iqmp)
            & self.p.ct_eq(&other.p)
            & self.q.ct_eq(&other.q)
    }
}

impl Debug for RsaPrivateKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RsaPrivateKey").finish_non_exhaustive()
    }
}

impl Drop for RsaPrivateKey {
    fn drop(&mut self) {
        self.d.zeroize();
        self.iqmp.zeroize();
        self.p.zeroize();
        self.q.zeroize();
    }
}

impl Decode for RsaPrivateKey {
    type Error = Error;

    fn decode(reader: &mut impl Reader) -> Result<Self> {
        let d = Mpint::decode(reader)?;
        let iqmp = Mpint::decode(reader)?;
        let p = Mpint::decode(reader)?;
        let q = Mpint::decode(reader)?;
        Self::new(d, iqmp, p, q)
    }
}

impl Encode for RsaPrivateKey {
    fn encoded_len(&self) -> encoding::Result<usize> {
        [
            self.d.encoded_len()?,
            self.iqmp.encoded_len()?,
            self.p.encoded_len()?,
            self.q.encoded_len()?,
        ]
        .checked_sum()
    }

    fn encode(&self, writer: &mut impl Writer) -> encoding::Result<()> {
        self.d.encode(writer)?;
        self.iqmp.encode(writer)?;
        self.p.encode(writer)?;
        self.q.encode(writer)?;
        Ok(())
    }
}

impl Eq for RsaPrivateKey {}
impl PartialEq for RsaPrivateKey {
    fn eq(&self, other: &Self) -> bool {
        self.ct_eq(other).into()
    }
}

/// RSA private/public keypair.
#[derive(Clone)]
pub struct RsaKeypair {
    /// Public key.
    public: RsaPublicKey,

    /// Private key.
    private: RsaPrivateKey,
}

impl RsaKeypair {
    /// Generate a random RSA keypair of the given size.
    #[cfg(feature = "rsa")]
    #[expect(clippy::missing_errors_doc, reason = "TODO")]
    pub fn random<R: CryptoRng + ?Sized>(rng: &mut R, bit_size: usize) -> Result<Self> {
        let _ = rng; // AWS-LC uses its independently seeded system CSPRNG.
        let size = match bit_size {
            2048 => aws_lc_rs::rsa::KeySize::Rsa2048,
            3072 => aws_lc_rs::rsa::KeySize::Rsa3072,
            4096 => aws_lc_rs::rsa::KeySize::Rsa4096,
            _ => return Err(Error::Crypto),
        };
        let key = aws_lc_rs::rsa::KeyPair::generate(size).map_err(|_| Error::Crypto)?;
        use aws_lc_rs::encoding::AsDer;
        let der: aws_lc_rs::encoding::Pkcs8V1Der<'static> =
            key.as_der().map_err(|_| Error::Crypto)?;
        // Decode the library-generated PKCS#8 envelope to its PKCS#1 contents.
        let doc = pkcs8::PrivateKeyInfoRef::try_from(der.as_ref()).map_err(|_| Error::Crypto)?;
        Self::from_pkcs1_der(doc.private_key.as_bytes())
    }

    /// Create a new keypair from the given `public` and `private` key components.
    ///
    /// # Errors
    /// Returns [`Error::Crypto`] if the `public` key does not match the `private` key (TODO).
    pub fn new(public: RsaPublicKey, private: RsaPrivateKey) -> Result<Self> {
        // TODO(tarcieri): perform validation that the public and private components match?
        Ok(Self { public, private })
    }

    /// Get the size of the RSA modulus in bits.
    #[must_use]
    pub fn key_size(&self) -> u32 {
        self.public.key_size()
    }

    /// Get the public component of the keypair.
    #[must_use]
    pub fn public(&self) -> &RsaPublicKey {
        &self.public
    }

    /// Get the private component of the keypair.
    #[must_use]
    pub fn private(&self) -> &RsaPrivateKey {
        &self.private
    }
}

impl CtEq for RsaKeypair {
    fn ct_eq(&self, other: &Self) -> Choice {
        Choice::from(u8::from(self.public == other.public)) & self.private.ct_eq(&other.private)
    }
}

impl Debug for RsaKeypair {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("RsaKeypair")
            .field("public", &self.public)
            .finish_non_exhaustive()
    }
}

impl Decode for RsaKeypair {
    type Error = Error;

    fn decode(reader: &mut impl Reader) -> Result<Self> {
        let n = Mpint::decode(reader)?;
        let e = Mpint::decode(reader)?;
        let public = RsaPublicKey::new(e, n)?;
        let private = RsaPrivateKey::decode(reader)?;
        Self::new(public, private)
    }
}

impl Encode for RsaKeypair {
    fn encoded_len(&self) -> encoding::Result<usize> {
        [
            self.public.n().encoded_len()?,
            self.public.e().encoded_len()?,
            self.private.encoded_len()?,
        ]
        .checked_sum()
    }

    fn encode(&self, writer: &mut impl Writer) -> encoding::Result<()> {
        self.public.n().encode(writer)?;
        self.public.e().encode(writer)?;
        self.private.encode(writer)
    }
}

impl Eq for RsaKeypair {}
impl PartialEq for RsaKeypair {
    fn eq(&self, other: &Self) -> bool {
        self.ct_eq(other).into()
    }
}

impl From<RsaKeypair> for RsaPublicKey {
    fn from(keypair: RsaKeypair) -> RsaPublicKey {
        keypair.public
    }
}

impl From<&RsaKeypair> for RsaPublicKey {
    fn from(keypair: &RsaKeypair) -> RsaPublicKey {
        keypair.public.clone()
    }
}

#[cfg(feature = "rsa")]
impl RsaKeypair {
    /// Validate and import a traditional PKCS#1 RSA key through AWS-LC.
    pub fn from_pkcs1_der(input: &[u8]) -> Result<Self> {
        aws_lc_rs::rsa::KeyPair::from_der(input).map_err(|_| Error::Crypto)?;
        let key = pkcs1::RsaPrivateKey::try_from(input).map_err(|_| Error::Crypto)?;
        if key.other_prime_infos.is_some() {
            return Err(Error::Crypto);
        }
        let public = RsaPublicKey::new(
            Mpint::from_positive_bytes(key.public_exponent.as_bytes()),
            Mpint::from_positive_bytes(key.modulus.as_bytes()),
        )?;
        let private = RsaPrivateKey::new(
            Mpint::from_positive_bytes(key.private_exponent.as_bytes()),
            Mpint::from_positive_bytes(key.coefficient.as_bytes()),
            Mpint::from_positive_bytes(key.prime1.as_bytes()),
            Mpint::from_positive_bytes(key.prime2.as_bytes()),
        )?;
        Self::new(public, private)
    }

    /// Import OpenSSH key components into the maintained RSA backend.
    pub(crate) fn to_aws_lc(&self) -> Result<aws_lc_rs::rsa::KeyPair> {
        use crypto_bigint::{BoxedUint, NonZero};
        use zeroize::Zeroizing;
        let n = self.public.n().as_positive_bytes().ok_or(Error::Crypto)?;
        let e = self.public.e().as_positive_bytes().ok_or(Error::Crypto)?;
        let d = self.private.d.as_positive_bytes().ok_or(Error::Crypto)?;
        let p = self.private.p.as_positive_bytes().ok_or(Error::Crypto)?;
        let q = self.private.q.as_positive_bytes().ok_or(Error::Crypto)?;
        let iqmp = self.private.iqmp.as_positive_bytes().ok_or(Error::Crypto)?;
        let precision = u32::try_from(n.len())
            .map_err(|_| Error::Crypto)?
            .checked_mul(8)
            .ok_or(Error::Crypto)?;
        let exponent =
            Zeroizing::new(BoxedUint::from_be_slice(d, precision).map_err(|_| Error::Crypto)?);
        let crt_exponent = |prime: &[u8]| -> Result<Zeroizing<Box<[u8]>>> {
            let prime = Zeroizing::new(
                BoxedUint::from_be_slice(prime, precision).map_err(|_| Error::Crypto)?,
            );
            let denominator = Zeroizing::new(
                Option::<NonZero<BoxedUint>>::from(NonZero::new(
                    prime.wrapping_sub(BoxedUint::one_with_precision(precision)),
                ))
                .ok_or(Error::Crypto)?,
            );
            // Use the maintained library's constant-time remainder, not rem_vartime.
            let remainder = Zeroizing::new(exponent.rem(&*denominator));
            Ok(Zeroizing::new(remainder.to_be_bytes()))
        };
        let dp = crt_exponent(p)?;
        let dq = crt_exponent(q)?;
        aws_lc_rs::rsa::KeyPair::from_components(&aws_lc_rs::rsa::KeyPairComponents {
            public_key: aws_lc_rs::rsa::PublicKeyComponents { n, e },
            d,
            p,
            q,
            dP: dp.as_ref(),
            dQ: dq.as_ref(),
            qInv: iqmp,
        })
        .map_err(|_| Error::Crypto)
    }

    /// Export PKCS#8 through AWS-LC, retaining the existing key format.
    pub fn to_pkcs8_der(&self) -> Result<Vec<u8>> {
        use aws_lc_rs::encoding::AsDer;
        let key = self.to_aws_lc()?;
        let der: aws_lc_rs::encoding::Pkcs8V1Der<'static> =
            key.as_der().map_err(|_| Error::Crypto)?;
        Ok(der.as_ref().to_vec())
    }
}
