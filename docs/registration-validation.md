# 配准数值对照

Windows 和 Linux 的 CI 都用 MoonBit 的 JS Release 构建执行以下对照，并保存 `registration-oracle.json`。NumPy 只在验证脚本中使用。

| 验证项 | 独立参考值 | 比对结果 |
| --- | --- | --- |
| 刚体、相似配准 | NumPy 对已知内点作奇异值分解，求旋转、平移和相似变换比例 | 每个模型三种角度，有噪声，并各测试有无一个离群点 |
| 仿射配准 | NumPy 直接对坐标设计矩阵作最小二乘拟合 | 同样比较仿射系数、平移、逐点残差、内点掩码和汇总误差 |
| 最小最大残差平移 | 构造三个围住已知圆心的边界偏移，最小包围半径为 0.05 mm | CLI 在 0.049999 mm 容差下给出 `indeterminate`，在 0.050001 mm 下给出 `pass`，并核对两次的平移及残差 |

前两行共 18 个固定种子的算例。每个算例检查 MoonBit 是否自己认出已知离群点，再与只使用已知内点的 NumPy 结果对比。坐标、平移和残差的绝对误差门槛为 `1e-9 mm`，线性系数、比例和以度计的角度门槛为 `1e-10`。铜层几何另见[焊盘容差对照](pad-tolerance-validation.md)。

```sh
moon build --target js --release
python -m pip install numpy==2.4.4
python tests/registration-oracle.py
```

参考方法见 [NumPy SVD](https://numpy.org/doc/2.4/reference/generated/numpy.linalg.svd.html) 和 [NumPy 最小二乘](https://numpy.org/doc/2.4/reference/generated/numpy.linalg.lstsq.html)。
