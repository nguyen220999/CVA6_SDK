/* The NPU is released with its PC set to the FIT load/entry address. */
__attribute__((noreturn, section(".text.entry"), used))
void main(void)
{
	while (1)
		;
}
