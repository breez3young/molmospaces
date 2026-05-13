import logging
import os
import time

import cv2
import numpy as np
from scipy.spatial.transform import Rotation as R

from molmo_spaces.policy.learned_policy.pi_policy import PI_Policy
from molmo_spaces.policy.learned_policy.utils import resize_with_pad

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


class PRTS_Policy(PI_Policy):
    """PRTS policy client over websocket.

    Uses the same DROID observation formatting and action decoding path as PI,
    but keeps a dedicated policy identity for evaluation bookkeeping.
    """

    def reset(self):
        self.actions_buffer = None
        self.current_buffer_index = 0
        self.starting_time = None

    def get_info(self) -> dict:
        info = super().get_info()
        if info.get("policy_name") in {None, "pi"}:
            info["policy_name"] = "prts"
        info["timestamp"] = time.time()
        return info

    def obs_to_model_input(self, obs):
        # self.render(obs)
        if isinstance(obs, list):
            if len(obs) > 1:
                log.warning(
                    "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
                    "WARNING: obs list has %d elements but only using the first one!\n"
                    "This may indicate a batching issue - expected single observation.\n"
                    "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",
                    len(obs),
                )
            obs = obs[0]
        model_input = {**obs}
        prompt = self.task.get_task_description()

        # For local eval
        if isinstance(obs, list | tuple):
            obs = obs[0]

        grip = np.clip(obs["qpos"]["gripper"][0] / 0.824033, 0, 1)
        exo_camera_key = (
            "droid_shoulder_light_randomization"
            if "droid_shoulder_light_randomization" in obs
            else "exo_camera_1"
        )
        wrist_camera_key = (
            "wrist_camera_zed_mini" if "wrist_camera_zed_mini" in obs else "wrist_camera"
        )

        # exo_image = obs[exo_camera_key]
        # save_dir = os.path.join(os.getcwd(), "debug_exo_images")
        # os.makedirs(save_dir, exist_ok=True)
        # filename = (
        #     f"exo_{int(time.time() * 1000)}_{self._saved_exo_image_count:06d}.png"
        # )
        # save_path = os.path.join(save_dir, filename)
        # try:
        #     cv2.imwrite(save_path, cv2.cvtColor(obs[exo_camera_key], cv2.COLOR_RGB2BGR))
        #     self._saved_exo_image_count += 1
        # except Exception as e:
        #     log.warning(f"Failed to save exo image to {save_path}: {e}")

        # get eef pose state
        # eef_pose = ee_pose_to_xyzrpy(np.array(obs['robot_state']['ee_pose']))

        joint_position = np.array(obs["qpos"]["arm"][:7]).reshape(7,)
        gripper_position = np.array(grip).reshape(1,)

        obs_state = np.concatenate([joint_position, gripper_position])

        ext = resize_with_pad(obs[exo_camera_key], 180, 320)
        wrist = resize_with_pad(obs[wrist_camera_key], 180, 320)

        flag = False
        if flag:
            d = os.environ.get("PRTS_SAVE_RESIZED_DIR", "prts_resized_debug")
            os.makedirs(d, exist_ok=True)
            t = int(time.time() * 1000)
            cv2.imwrite(
                os.path.join(d, f"exterior_1_left_{t}.png"),
                cv2.cvtColor(np.asarray(ext), cv2.COLOR_RGB2BGR),
            )
            cv2.imwrite(
                os.path.join(d, f"wrist_left_{t}.png"),
                cv2.cvtColor(np.asarray(wrist), cv2.COLOR_RGB2BGR),
            )

        model_input = {
            "observation/exterior_1_left": ext,
            "observation/wrist_left": wrist,
            "observation/state": obs_state,
            "prompt": prompt.lower(),
        }
        return model_input
    
    def inference_model(self, model_input):
        if self.model is None:
            self.prepare_model()
        if self.starting_time is None:
            self.starting_time = time.time()
        if self.actions_buffer is None or self.current_buffer_index >= self.chunk_size:
            import websockets

            try:
                self.actions_buffer = self.model.infer(model_input)["actions"]
            except websockets.exceptions.ConnectionClosedError:
                log.error("Connection closed error. Attempting to reset connection...")
                self.prepare_model()
                log.info("Sleeping 5s...")
                time.sleep(5)
                log.info("Retrying inference...")
                self.actions_buffer = self.model.infer(model_input)["actions"]
            self.current_buffer_index = 0
        model_output = self.actions_buffer[self.current_buffer_index]
        self.current_buffer_index += 1
        return model_output

    def model_output_to_action(self, model_output):
        if self.grasping_type == "continuous":
            gripper_pos = model_output[7] * np.array([255.0])
        else:  # binary
            gripper_pos = (
                np.array([255.0]) if model_output[7] > self.grasping_threshold else np.array([0.0])
            )

        arm_output = model_output[:7].reshape(
            7,
        )
        action = {
            "arm": arm_output,
            "gripper": gripper_pos,
        }
        return action