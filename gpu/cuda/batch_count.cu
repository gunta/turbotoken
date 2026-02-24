extern "C" __global__ void batch_count(const unsigned char *input, unsigned int *output, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) output[i] = input[i] ? 1u : 0u;
}
