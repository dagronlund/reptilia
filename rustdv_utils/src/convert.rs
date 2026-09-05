use indiscriminant::BitWidth;
use rustdv::prelude::*;

pub trait LogicArrayDecode<Repr>: Sized {
    fn decode(payload: &LogicHandle) -> Result<Self, TestError>;
}

impl<T> LogicArrayDecode<u8> for T
where
    T: BitWidth + From<u8>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_u8()?))
    }
}

impl<T> LogicArrayDecode<u16> for T
where
    T: BitWidth + From<u16>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_u16()?))
    }
}

impl<T> LogicArrayDecode<u32> for T
where
    T: BitWidth + From<u32>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_u32()?))
    }
}

impl<T> LogicArrayDecode<u64> for T
where
    T: BitWidth + From<u64>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_u64()?))
    }
}

impl<T> LogicArrayDecode<u128> for T
where
    T: BitWidth + From<u128>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_u128()?))
    }
}

impl<T> LogicArrayDecode<BigUint> for T
where
    T: BitWidth + From<BigUint>,
{
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self::from(payload.get_bigint()?))
    }
}

pub trait LogicArrayTryDecode<Repr>: Sized {
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError>;
}

impl<T> LogicArrayTryDecode<u8> for T
where
    T: BitWidth + TryFrom<u8>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_u8()?)
            .map_err(|_| TestError::new("Failed to convert u8 to target type"))
    }
}

impl<T> LogicArrayTryDecode<u16> for T
where
    T: BitWidth + TryFrom<u16>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_u16()?)
            .map_err(|_| TestError::new("Failed to convert u16 to target type"))
    }
}

impl<T> LogicArrayTryDecode<u32> for T
where
    T: BitWidth + TryFrom<u32>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_u32()?)
            .map_err(|_| TestError::new("Failed to convert u32 to target type"))
    }
}

impl<T> LogicArrayTryDecode<u64> for T
where
    T: BitWidth + TryFrom<u64>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_u64()?)
            .map_err(|_| TestError::new("Failed to convert u64 to target type"))
    }
}

impl<T> LogicArrayTryDecode<u128> for T
where
    T: BitWidth + TryFrom<u128>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_u128()?)
            .map_err(|_| TestError::new("Failed to convert u128 to target type"))
    }
}

impl<T> LogicArrayTryDecode<BigUint> for T
where
    T: BitWidth + TryFrom<BigUint>,
{
    fn try_decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Self::try_from(payload.get_bigint()?)
            .map_err(|_| TestError::new("Failed to convert BigUint to target type"))
    }
}

pub trait LogicArrayEncode<Repr> {
    fn encode(self) -> LogicArray;
}

impl<T> LogicArrayEncode<u8> for T
where
    T: BitWidth + Into<u8>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_u8(self.into(), Self::bit_width())
    }
}

impl<T> LogicArrayEncode<u16> for T
where
    T: BitWidth + Into<u16>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_u16(self.into(), Self::bit_width())
    }
}

impl<T> LogicArrayEncode<u32> for T
where
    T: BitWidth + Into<u32>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_u32(self.into(), Self::bit_width())
    }
}

impl<T> LogicArrayEncode<u64> for T
where
    T: BitWidth + Into<u64>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_u64(self.into(), Self::bit_width())
    }
}

impl<T> LogicArrayEncode<u128> for T
where
    T: BitWidth + Into<u128>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_u128(self.into(), Self::bit_width())
    }
}

impl<T> LogicArrayEncode<BigUint> for T
where
    T: BitWidth + Into<BigUint>,
{
    fn encode(self) -> LogicArray {
        LogicArray::from_bigint(&self.into(), Self::bit_width())
    }
}
